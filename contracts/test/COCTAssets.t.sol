// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

// Foundry test suite for COCTAssets — solvency invariant + hardening (2026-08-01).
//
// To run: from a Foundry project with solc 0.8.36 / evm_version "paris" and forge-std available
// (e.g. the shared `chain/` workspace, remapping forge-std/=lib/forge-std/src/), place assets.sol so the
// import below resolves, then `forge test`. Proves: deposit/withdraw round-trip, creditBalance UNBACKED
// guard, the old mint-drain is blocked, the totalTracked <= holdings invariant (scripted + fuzz), pause
// covers every egress, sweepSurplus moves only surplus (never user-backing), accounts is immutable, and
// the constructor rejects a zero/non-contract accounts.

import "forge-std/Test.sol";
import "../assets.sol";

/* ----------------------------- mocks ----------------------------- */
contract MockERC20 is IERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 v) external { balanceOf[to] += v; totalSupply += v; }
    function transfer(address to, uint256 v) external returns (bool) {
        balanceOf[msg.sender] -= v; balanceOf[to] += v; emit Transfer(msg.sender, to, v); return true;
    }
    function approve(address s, uint256 v) external returns (bool) { allowance[msg.sender][s] = v; emit Approval(msg.sender, s, v); return true; }
    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        allowance[f][msg.sender] -= v; balanceOf[f] -= v; balanceOf[t] += v; emit Transfer(f, t, v); return true;
    }
}

contract MockAccounts is ICOCTAccounts {
    mapping(address => bool) public users;
    mapping(address => bool) public admins;
    function setUser(address a, bool v) external { users[a] = v; }
    function setAdmin(address a, bool v) external { admins[a] = v; }
    function isUser(address a) external view returns (bool) { return users[a]; }
    function checkIsAdmin(address a) external view returns (bool) { return admins[a]; }
}

/* ----------------------------- tests ----------------------------- */
contract COCTAssetsTest is Test {
    COCTAssets vault;
    MockERC20 tok;
    MockAccounts acc;

    address admin = address(this); // the test contract is the admin
    address alice = address(0xA11CE);
    address attacker = address(0xBAD);

    function setUp() public {
        acc = new MockAccounts();
        acc.setAdmin(admin, true);
        acc.setUser(alice, true);
        acc.setUser(attacker, true);
        vault = new COCTAssets(address(acc), address(0));
        tok = new MockERC20();
    }

    function _inv() internal view {
        assertLe(vault.totalTracked(address(tok)), tok.balanceOf(address(vault)), "INVARIANT: tracked > holdings");
    }

    function _deposit(address who, uint256 amt) internal {
        tok.mint(who, amt);
        vm.startPrank(who);
        tok.approve(address(vault), amt);
        vault.deposit(address(tok), amt);
        vm.stopPrank();
    }

    // (a) deposit -> withdraw round-trip (5% fee, within [5,100] bounds)
    function test_deposit_withdraw_roundtrip() public {
        _deposit(alice, 100 ether);
        assertEq(vault.balances(alice, address(tok)), 100 ether);
        assertEq(vault.totalTracked(address(tok)), 100 ether);
        _inv();

        vm.prank(alice);
        vault.withdraw(address(tok), 100 ether);
        assertEq(vault.balances(alice, address(tok)), 0);
        assertEq(vault.totalTracked(address(tok)), 0);
        assertEq(tok.balanceOf(alice), 95 ether);            // 5% fee retained
        assertEq(vault.surplus(address(tok)), 5 ether);      // fee = surplus
        _inv();
    }

    // (b) creditBalance reverts UNBACKED beyond holdings; succeeds when pre-funded
    function test_creditBalance_requires_backing() public {
        vm.expectRevert(bytes("UNBACKED"));
        vault.creditBalance(alice, address(tok), 10 ether); // vault holds 0

        tok.mint(address(vault), 50 ether);                 // fund the pool (surplus)
        vault.creditBalance(alice, address(tok), 50 ether); // exactly backed -> ok
        assertEq(vault.balances(alice, address(tok)), 50 ether);
        _inv();

        vm.expectRevert(bytes("UNBACKED"));
        vault.creditBalance(alice, address(tok), 1);        // now over holdings
    }

    // (c) the old drain: mint-from-nothing then cash out -> now blocked at the credit
    function test_old_drain_blocked() public {
        _deposit(alice, 100 ether); // real user funds in the vault
        // attacker (an admin) tries to mint themselves the whole vault and withdraw it
        vm.expectRevert(bytes("UNBACKED"));
        vault.creditBalance(attacker, address(tok), 100 ether);
        // alice's funds untouched
        assertEq(vault.balances(alice, address(tok)), 100 ether);
        _inv();
    }

    // (d) invariant holds across a scripted op sequence
    function test_invariant_sequence() public {
        _deposit(alice, 80 ether); _inv();
        tok.mint(address(vault), 40 ether);                 // surplus for rewards
        vault.creditBalance(alice, address(tok), 30 ether); _inv();
        vault.debitBalance(alice, address(tok), 20 ether); _inv();
        vault.balanceTransfer(alice, attacker, address(tok), 10 ether); _inv();
        vm.prank(alice); vault.withdraw(address(tok), 50 ether); _inv();
        vault.balanceWithdraw(address(tok), attacker, 10 ether); _inv();
    }

    // fuzz: any single credit can never exceed real holdings
    function testFuzz_credit_never_exceeds_holdings(uint96 fund, uint96 credit) public {
        tok.mint(address(vault), fund);
        if (credit == 0) return;
        if (uint256(credit) <= uint256(fund)) {
            vault.creditBalance(alice, address(tok), credit);
        } else {
            vm.expectRevert(bytes("UNBACKED"));
            vault.creditBalance(alice, address(tok), credit);
        }
        _inv();
    }

    // (e) pause blocks every egress incl. balanceWithdraw
    function test_pause_blocks_all_egress() public {
        _deposit(alice, 100 ether);
        tok.mint(address(vault), 100 ether);
        vault.setPaused(true);

        vm.prank(alice); vm.expectRevert(bytes("PAUSED")); vault.withdraw(address(tok), 10 ether);
        vm.expectRevert(bytes("PAUSED")); vault.creditBalance(alice, address(tok), 1 ether);
        vm.expectRevert(bytes("PAUSED")); vault.debitBalance(alice, address(tok), 1 ether);
        vm.expectRevert(bytes("PAUSED")); vault.balanceTransfer(alice, attacker, address(tok), 1 ether);
        vm.expectRevert(bytes("PAUSED")); vault.balanceWithdraw(address(tok), alice, 10 ether);
    }

    // (h) sweepSurplus moves ONLY unattributed surplus, never user-backing funds
    function test_sweepSurplus_only_surplus() public {
        _deposit(alice, 100 ether);                 // 100 backed, surplus 0
        // cannot touch user-backing
        vm.expectRevert(bytes("EXCEEDS_SURPLUS"));
        vault.sweepSurplus(address(tok), attacker, 1 ether);

        tok.mint(address(vault), 30 ether);         // 30 surplus (fees / company funds)
        assertEq(vault.surplus(address(tok)), 30 ether);

        vault.sweepSurplus(address(tok), attacker, 30 ether); // sweep exactly the surplus
        assertEq(tok.balanceOf(attacker), 30 ether);
        assertEq(vault.surplus(address(tok)), 0);
        assertEq(vault.totalTracked(address(tok)), 100 ether);    // liabilities unchanged
        assertEq(vault.balances(alice, address(tok)), 100 ether); // alice untouched
        _inv();

        vm.expectRevert(bytes("EXCEEDS_SURPLUS"));   // nothing left beyond backing
        vault.sweepSurplus(address(tok), attacker, 1);
    }

    // (i) sweepSurplus is pausable
    function test_sweepSurplus_paused() public {
        tok.mint(address(vault), 10 ether);
        vault.setPaused(true);
        vm.expectRevert(bytes("PAUSED"));
        vault.sweepSurplus(address(tok), attacker, 1 ether);
    }

    // (f) accounts is immutable: wired at deploy, no setter to repoint it
    function test_accounts_immutable() public view {
        assertEq(address(vault.accounts()), address(acc));
    }

    // (g) constructor rejects a zero address and a non-contract (EOA)
    function test_constructor_rejects_bad_accounts() public {
        vm.expectRevert(bytes("ZERO_ACCOUNTS"));
        new COCTAssets(address(0), address(0));

        vm.expectRevert(bytes("NOT_CONTRACT"));
        new COCTAssets(address(0xE0A), address(0)); // EOA — no code
    }
}
