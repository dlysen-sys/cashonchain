// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

// Foundry test suite for COCTMembership — subscribe fee-split conservation + the two hardenings
// (2026-08-02): (1) LP routing always resets the manager allowance and reclaims any un-pulled USDT to the
// vault; (2) zero-amount unilevel/community credits are skipped so a tiny-fee config can't revert subscribe.
//
// Only membership.sol is imported (assets.sol shares interface names — importing both collides). A MockAssets
// reproduces the vault semantics membership relies on: creditBalance/sweepSurplus revert on a zero amount
// (mirroring the real COCTAssets ZERO_AMOUNT), and sweepSurplus moves real USDT. Run from a Foundry project
// with solc 0.8.36 + forge-std.

import "forge-std/Test.sol";
import "../membership.sol";

/* ------------------------------- mocks ------------------------------- */
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 v) external { balanceOf[to] += v; }
    function approve(address s, uint256 v) external returns (bool) { allowance[msg.sender][s] = v; return true; }
    function transfer(address to, uint256 v) external returns (bool) {
        balanceOf[msg.sender] -= v; balanceOf[to] += v; return true;
    }
    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        allowance[f][msg.sender] -= v; balanceOf[f] -= v; balanceOf[t] += v; return true;
    }
}

contract MockAccounts is ICOCTAccounts {
    mapping(address => bool) public users;
    mapping(address => bool) public admins;
    mapping(address => address) public sponsorOf;
    mapping(address => uint256) public directs;
    function setUser(address a, bool v) external { users[a] = v; }
    function setAdmin(address a, bool v) external { admins[a] = v; }
    function isUser(address a) external view returns (bool) { return users[a]; }
    function checkIsAdmin(address a) external view returns (bool) { return admins[a]; }
    function addUser(address user, address sponsor) external {
        require(!users[user], "ALREADY");
        require(users[sponsor], "SPONSOR");
        users[user] = true; sponsorOf[user] = sponsor; directs[sponsor] += 1;
    }
    function getAffiliate(address user) external view returns (address, uint256) {
        return (sponsorOf[user], directs[user]);
    }
}

// Reproduces the vault semantics membership depends on. `fund` seeds a ledger balance AND (via the test)
// real USDT holdings, simulating a deposit. creditBalance/sweepSurplus reject zero (like COCTAssets).
contract MockAssets is ICOCTAssets {
    mapping(address => mapping(address => uint256)) public bal;
    function fund(address u, address t, uint256 a) external { bal[u][t] += a; }
    function balanceOf(address u, address t) external view returns (uint256) { return bal[u][t]; }
    function debitBalance(address u, address t, uint256 a) external { require(bal[u][t] >= a, "INSUFFICIENT_BALANCE"); bal[u][t] -= a; }
    function creditBalance(address u, address t, uint256 a) external { require(a > 0, "ZERO_AMOUNT"); bal[u][t] += a; }
    function sweepSurplus(address t, address to, uint256 a) external {
        require(a > 0, "ZERO_AMOUNT");
        require(MockERC20(t).balanceOf(address(this)) >= a, "EXCEEDS_SURPLUS");
        MockERC20(t).transfer(to, a);
    }
}

contract MockLiquidity is ILiquidity {
    uint256 public tokenId;
    uint256 public pullAmount;
    uint256 public ret;
    bool public doRevert;
    address public usdt;
    constructor(address _usdt) { usdt = _usdt; }
    function config(uint256 _t, uint256 _pull, uint256 _ret, bool _rev) external {
        tokenId = _t; pullAmount = _pull; ret = _ret; doRevert = _rev;
    }
    function TOKENID() external view returns (uint256) { return tokenId; }
    function addLiquidityUSDT(uint256, uint24, uint256) external returns (uint256) {
        if (doRevert) revert("LP_REVERT");
        if (pullAmount > 0) MockERC20(usdt).transferFrom(msg.sender, address(this), pullAmount);
        return ret;
    }
}

/* ------------------------------- tests ------------------------------- */
contract COCTMembershipTest is Test {
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955; // membership hardcodes this

    MockERC20 usdt;
    MockAccounts acc;
    MockAssets vault;
    COCTMembership hub;
    MockLiquidity lp;

    address root = address(0x1111);
    address alice = address(0xA11CE);
    address liqW = address(0x101);
    address gasW = address(0x102);
    address commW = address(0x103);
    address opexW = address(0x104);

    function setUp() public {
        vm.etch(USDT, address(new MockERC20()).code); // put a token at the hardcoded USDT address
        usdt = MockERC20(USDT);

        acc = new MockAccounts();
        vault = new MockAssets();
        hub = new COCTMembership(address(acc), address(vault), address(0));
        lp = new MockLiquidity(USDT);

        acc.setAdmin(address(this), true); // test = admin (setWallets/setParams/setLiquidity)
        acc.setAdmin(address(hub), true);  // hub  = admin (addUser/debit/credit/sweep)
        acc.setUser(root, true);
        hub.setWallets(liqW, gasW, commW, opexW);
    }

    function _reg(address u, address sponsor) internal { vm.prank(u); hub.register(sponsor); }
    function _fund(address u, uint256 amt) internal { usdt.mint(address(vault), amt); vault.fund(u, USDT, amt); }
    function _sub(address u) internal { vm.prank(u); hub.subscribe(); }

    // Fee split conserves the $20 exactly (no LP manager → liquidity to the vault wallet).
    function test_subscribe_conserves_fee() public {
        _reg(alice, root);
        _fund(alice, 20 ether);
        _sub(alice);

        assertTrue(hub.isSubscribed(alice));
        assertEq(vault.balanceOf(alice, USDT), 0);          // fee debited
        assertEq(vault.balanceOf(gasW, USDT), 1.5 ether);
        assertEq(vault.balanceOf(opexW, USDT), 12.5 ether); // 6.5 opex + 6 unilevel residual (root inactive)
        assertEq(vault.balanceOf(liqW, USDT), 5 ether);
        assertEq(vault.balanceOf(commW, USDT), 1 ether);    // community fallback (shallow tree)
        // 0 + 1.5 + 12.5 + 5 + 1 = 20 == fee
    }

    // Hardening 1 — partial pull: allowance reset to 0, un-pulled USDT reclaimed to the vault, none stranded.
    function test_h1_partial_pull_reclaims() public {
        _reg(alice, root);
        _fund(alice, 20 ether);
        hub.setLiquidity(address(lp));
        lp.config(1, 3 ether, 1, false); // ready; pulls 3 of 5; reports success

        _sub(alice);

        assertEq(usdt.balanceOf(address(hub)), 0, "no stranded USDT in hub");
        assertEq(usdt.allowance(address(hub), address(lp)), 0, "allowance reset");
        assertEq(usdt.balanceOf(address(lp)), 3 ether, "LP took 3");
        assertEq(vault.balanceOf(liqW, USDT), 2 ether, "leftover 2 reclaimed to liquidity wallet");
    }

    // Hardening 1 — clean full pull: nothing left, allowance reset, nothing re-credited.
    function test_h1_full_pull() public {
        _reg(alice, root);
        _fund(alice, 20 ether);
        hub.setLiquidity(address(lp));
        lp.config(1, 5 ether, 1, false); // pulls the full 5

        _sub(alice);

        assertEq(usdt.balanceOf(address(hub)), 0);
        assertEq(usdt.allowance(address(hub), address(lp)), 0);
        assertEq(usdt.balanceOf(address(lp)), 5 ether);
        assertEq(vault.balanceOf(liqW, USDT), 0);
    }

    // Hardening 1 — manager reverts: full amount reclaimed to the vault, allowance cleared.
    function test_h1_failure_reclaims_all() public {
        _reg(alice, root);
        _fund(alice, 20 ether);
        hub.setLiquidity(address(lp));
        lp.config(1, 0, 0, true); // ready but reverts

        _sub(alice);

        assertEq(usdt.balanceOf(address(hub)), 0);
        assertEq(usdt.allowance(address(hub), address(lp)), 0);
        assertEq(vault.balanceOf(liqW, USDT), 5 ether, "full liquidity slice reclaimed");
    }

    // Hardening 2 — a tiny fee drives perLevel and communityReward to 0; subscribe must NOT revert
    // (pre-hardening the zero-amount creditBalance calls reverted ZERO_AMOUNT).
    function test_h2_zero_amount_credits_do_not_revert() public {
        _reg(alice, root);
        _fund(root, 20 ether); _sub(root);   // root becomes an active subscriber
        _fund(alice, 20 ether); _sub(alice); // alice's 1st sub → qualifiedDirects[root] = 1 (root now earns)

        hub.setParams(19, 90 days, 20);      // fee = 19 wei → perLevel = 0 and communityReward = 0
        _fund(alice, 19);

        vm.prank(alice);
        hub.subscribe();                     // would revert ZERO_AMOUNT without the guards

        assertTrue(hub.isSubscribed(alice));
    }

    // First subscription = base + promo (90 days); each renewal stacks only the base (30 days).
    function test_first_sub_90_then_renewal_30() public {
        _reg(alice, root);
        _fund(alice, 40 ether); // two $20 subscriptions
        uint256 t0 = block.timestamp;

        _sub(alice); // first-ever → 30 + 60 = 90 days
        assertEq(hub.subscriptionExpiry(alice), t0 + 90 days, "first term = 90 days");

        _sub(alice); // renewal → + 30 days, stacked on the remaining time
        assertEq(hub.subscriptionExpiry(alice), t0 + 120 days, "renewal adds 30 days");
    }

    // setPromoDuration(0) disables the promo → the first subscription is just the base 30 days.
    function test_promo_disabled_first_sub_is_base_only() public {
        hub.setPromoDuration(0);
        _reg(alice, root);
        _fund(alice, 20 ether);
        uint256 t0 = block.timestamp;

        _sub(alice);
        assertEq(hub.subscriptionExpiry(alice), t0 + 30 days, "no promo means base only");
    }

    // Lifetime unilevel income accumulates per earner across every payout.
    function test_unilevel_income_tracked() public {
        _reg(alice, root);
        _fund(root, 20 ether); _sub(root);    // root = active subscriber
        _fund(alice, 20 ether); _sub(alice);  // alice 1st sub → qualifiedDirects[root]=1, root earns $0.30
        assertEq(hub.unilevelIncome(root), 0.3 ether, "root earned one level");

        _fund(alice, 20 ether); _sub(alice);  // renewal → root earns another $0.30
        assertEq(hub.unilevelIncome(root), 0.6 ether, "lifetime accumulates");
        assertEq(hub.unilevelIncome(alice), 0, "alice earned nothing (no active downline)");
    }
}
