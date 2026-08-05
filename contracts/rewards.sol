// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/*
 *  ██████╗ ██████╗  ██████╗    ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗
 * ██╔════╝██╔═══██╗██╔════╝    ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║
 * ██║     ██║   ██║██║            ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║
 * ██║     ██║   ██║██║            ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║
 * ╚██████╗╚██████╔╝╚██████╗       ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║
 *  ╚═════╝ ╚═════╝  ╚═════╝       ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝
 *
 * Rewards Module — the COC compensation-plan hub (see docs/REWARDS.md, the source of truth).
 *
 * Six entry tiers (Silver..Black Diamond), 5 cycles each except Black Diamond (unlimited). Each entry:
 * splits 100% (10 opex / 5 agent / 5 override / 1 product / 79 token-liquidity), accrues a flat 1% COCT product,
 * and raises a single 200% income cap by 2x the entry. Five earning streams — Direct Referral (5%),
 * Daily Passive (1%/day own), Direct Passive (50% referral-L1 mirror), Line Income (10%x10 line-tree
 * mirror, auto-compressed past inactive uplines), and rank-differential Override — all draw down that
 * income cap and accrue to `rewardsBalance`. `withdrawRewards` credits the exact net (minus the stability
 * haircut) straight to the member's COCTAssets vault balance; the vault is REAL-BALANCE-as-truth and
 * inflow-funded (see COCTAssets: `totalWithdrawable` may exceed holdings; withdraw is real-balance gated).
 */

/* -------------------------------------------------------------------------- */
/*                            Dependency interfaces                           */
/* -------------------------------------------------------------------------- */
/// @notice COCTAccounts — the referral tree + global one-line + membership authority (source of truth).
interface ICOCTAccounts {
    function isUser(address account) external view returns (bool);
    function checkIsAdmin(address account) external view returns (bool);
    function addUser(address user, address sponsor) external;
    /// @return referral The user's direct referral sponsor. @return directCount Their direct count.
    function getAffiliate(address user) external view returns (address referral, uint256 directCount);
    /// @notice The global one-line node: `parent` = member registered immediately before `user`.
    function line(address user) external view returns (address parent, address child);
    /// @notice The structural root anchor (excluded from earning).
    function root() external view returns (address);
}

/// @notice COCTAssets — the solvency-guarded custody vault. Rewards debits entries and moves rewards.
interface ICOCTAssets {
    function balanceOf(address user, address token) external view returns (uint256);
    function debitBalance(address user, address token, uint256 amount) external;
    function creditBalance(address user, address token, uint256 amount) external;
    function depositFor(address user, address token, uint256 amount) external;
    function sweepSurplus(address token, address to, uint256 amount) external;
}

/// @notice Minimal COCTLiquidity surface: addLiquidityUSDT pulls USDT (approve first); TOKENID is 0 until
///         the LP position is initialized.
interface ILiquidity {
    function addLiquidityUSDT(uint256 usdtAmount, uint24 slippageBps, uint256 deadline)
        external returns (uint256);
    /// @notice Swap `usdtAmount` USDT → COCT (pulls USDT from the caller) and send the COCT to `recipient`.
    function swapUSDTToCOCT(uint256 usdtAmount, uint24 slippageBps, address recipient, uint256 deadline)
        external returns (uint256 amountOut);
    function TOKENID() external view returns (uint256);
}

/// @notice Minimal BEP20 surface (approve/transfer/balanceOf) for LP routing; `_safe*` tolerate BSC-USD.
interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/* -------------------------------------------------------------------------- */
/*                       ReentrancyGuard (minimal, inlined)                   */
/* -------------------------------------------------------------------------- */
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    modifier nonReentrant() {
        require(_status == 1, "REENTRANCY");
        _status = 2;
        _;
        _status = 1;
    }
}

/* -------------------------------------------------------------------------- */
/*                          Ownable (renounceable)                            */
/* -------------------------------------------------------------------------- */
/// @title Ownable (renounceable)
/// @author COCT
/// @notice A single-owner role that exists ONLY as a public decentralization signal. The owner holds NO
///         operational powers in this hub — EVERY management function is gated by `onlyAuth` (COCTAccounts
///         admin), never by `onlyOwner`. The owner may transfer the role or RENOUNCE it (owner →
///         address(0)); renouncing does NOT touch `onlyAuth`, so the admins registered in COCTAccounts keep
///         managing the hub exactly as before. This lets the project publish "ownership renounced" on
///         BscScan while operations continue through the accounts admin set.
/// @dev Renounce is one-way: once `_owner` is address(0), `onlyOwner` can never pass again, so no further
///      transfer or renounce is possible.
abstract contract Ownable {
    /// @dev The current owner (powerless signal role); address(0) once renounced.
    address private _owner;

    /// @notice Emitted on the initial owner set, on transfer, and on renounce (newOwner == address(0)).
    /// @param previousOwner The prior owner (address(0) at construction).
    /// @param newOwner The new owner (address(0) when renounced).
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Set the initial owner at deployment.
    /// @param initialOwner The address to record as the first owner (the deployer).
    constructor(address initialOwner) {
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @dev Restricts a function to the current owner; reverts NOT_OWNER otherwise. Used only by the
    ///      transfer/renounce signal functions below — never by any operational management function.
    modifier onlyOwner() {
        require(msg.sender == _owner, "NOT_OWNER");
        _;
    }

    /// @notice The current owner, or address(0) if ownership has been renounced.
    /// @return The owner address.
    function owner() public view returns (address) {
        return _owner;
    }

    /// @notice Transfer the (powerless) owner role to `newOwner`. Owner-only.
    /// @param newOwner The address to become the new owner; must be non-zero (use renounceOwnership to clear).
    /// @dev Does not affect `onlyAuth`. Reverts ZERO_ADDRESS.
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO_ADDRESS");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /// @notice Renounce ownership, setting the owner to address(0). Owner-only, one-way.
    /// @dev Operational control is UNCHANGED — every setter is `onlyAuth` (COCTAccounts admin), so the hub
    ///      keeps being managed after renounce. Provided so the project can signal a renounced owner.
    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

/* ========================================================================== */
/*                                 COCTRewards                                */
/* ========================================================================== */
/// @title COCTRewards
/// @author COCT
/// @notice The COC compensation-plan hub. Registered as a COCTAccounts admin (accounts.addAdmin), which
///         authorizes it to addUser on accounts and debit/credit/transfer balances on the vault.
/// @dev Self-contained (inlined ReentrancyGuard). Cap-drawing rewards accrue to `rewardsBalance` and are
///      credited to the member's vault balance at `withdrawRewards` (real-balance-gated cash-out on the
///      inflow-funded vault); each draws the payee's single 200% income cap. See docs/REWARDS.md.
contract COCTRewards is ReentrancyGuard, Ownable {
    uint256 private constant BPS = 10_000;

    /// @notice BSC-mainnet USDT (18-dp) — the settlement token.
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    /// @notice COCT token (18-dp) — the product token (accrued now, redeemed to COCT in a later phase).
    address public constant COCT = 0x13c6f832A8eA9D450FBc04c73b59D2A66ae12A77;

    /* ------------------------------- Wiring ---------------------------- */
    /// @notice COCTAccounts — referral tree + global one-line. Immutable.
    ICOCTAccounts public immutable accounts;
    /// @notice COCTAssets vault. Immutable.
    ICOCTAssets public assets;
    /// @notice The structural root anchor (cached from accounts) — excluded from all earning streams.
    address public immutable root;
    /// @notice External COCTLiquidity manager. address(0) / uninitialized disables LP routing.
    ILiquidity public liquidity;
    /// @notice Max slippage (bps) passed to the LP manager. Default 3%.
    uint256 public liquiditySlippageBps = 300;

    /* ------------------------------- Wallets --------------------------- */
    /// @notice Receives the 10% Opex (operating-expense) allocation — paid out as REAL USDT on each activation (sweepSurplus).
    address public opexWallet;
    /// @notice THE DEDICATED AGENT POOL — receives the 5% Agent allocation (vault balance). `claimAgentRewards`
    ///         pays the first agent up the tree FROM this pool, isolated from the reward/payout pool.
    address public agentWallet;
    /// @notice THE DEDICATED PRODUCT POOL — receives the 1% Product allocation (vault balance, USDT). `claimToken`
    ///         funds the USDT→COCT market swap FROM this pool, isolated from the reward/agent pools.
    address public productWallet;
    /// @notice THE REWARD / PAYOUT-BUFFER POOL — receives the 5% Override reserve + the retained Token-Liquidity
    ///         share (39% when LP is live, else 79%). Under the real-balance model its accumulated USDT is
    ///         part of the vault's real holdings that back reward cash-outs; it is not drawn directly by
    ///         `withdrawRewards` (which credits members' balances) — it is the on-chain funding buffer.
    address public liquidityWallet;

    /* --------------------------- Split (bps of entry) ------------------ */
    uint256 public opexBps = 1_000;           // 10% → real USDT to opexWallet
    uint256 public overrideBps = 500;         // 5%  → reserved into the reward pool (funds override payouts)
    uint256 public tokenLiquidityBps = 7_900; // 79% (opex+agent+override+product+tokenLiquidity == BPS)
    uint256 public lpBps = 4_000;             // of the entry: portion of the 79% routed to the LP (rest → pool)

    /* --------------------------- Earning params ------------------------ */
    uint256 public directReferralBps = 500;   // 5% to the referral-L1 sponsor, instant
    uint256 public directPassiveBps = 5_000;  // 50% referral-L1 mirror principal
    uint256 public lineIncomeBps = 1_000;     // 10% per line level mirror principal
    uint256 public lineLevels = 10;           // line-tree depth for Line Income
    uint256 public overrideMaxDepth = 100;    // referral-tree walk cap for Override (reused by Agent)
    uint256 public agentBps = 500;            // 5% to the first agent up the referral tree (UNCAPPED leader incentive)
    uint256 public dailyPassiveBps = 100;     // 1%/day accrual on every mirror
    uint256 public passiveCapBps = 20_000;    // 200% max payout per mirror tranche
    uint256 public incomeCapBps = 20_000;     // +200% (2x entry) added to the income cap per activation
    uint256 public oneDay = 1 days;           // accrual period (configurable for testing)
    uint256 public maxPackages = 200;         // per-array tranche cap (bounds claim loops)
    uint256 public productRate = 100 ether;   // COCT delivered per 1 USDT of accrued product (1e18-scaled):
                                              // coctOut = tokenBalance × productRate / 1e18. FALLBACK/INITIAL
                                              // default = 100e18 → 100 COCT per USDT = $0.01/COCT floor price.
                                              // productRate = 1e18 / price; retune later via setProductRate.

    /* ------------------------------- Tiers ----------------------------- */
    /// @notice Entry amount per tier: [Silver, Gold, Platinum, Diamond, Emerald, Black Diamond].
    uint256[6] public tierEntry;
    /// @notice Product COCT entitlement as a FLAT % (bps) of every entry, all tiers. Default 1%.
    uint256 public productBps = 100;
    /// @notice Override % (bps) per tier: [0,1,2,3,4,5]% (Silver..Black Diamond).
    uint256[6] public tierOverrideBps;
    /// @notice Stability fee (bps) per tier for Silver..Emerald, applied on `withdrawRewards`; Black Diamond
    ///         (index 5) uses bdStabilityBps instead (cycle-scaled).
    uint256[6] public tierStabilityBps;
    /// @notice Black Diamond stability fee (bps) by BD cycle: [1st,2nd,3rd,4th,5th+] = [10,15,20,25,30]%.
    uint256[5] public bdStabilityBps;

    /* ------------------------------- State ----------------------------- */
    /// @notice A mirror tranche: `amount` accrues `dailyPassiveBps`/day (from `startTime`) up to `maxPayout`;
    ///         `totalClaimed` is the amount already paid out. Accrual is startTime-based, so partial and
    ///         cap-clamped claims need no lastClaim bookkeeping.
    struct PassiveData {
        uint256 amount;
        uint256 startTime;
        uint256 totalClaimed;
        uint256 maxPayout;
    }

    /// @notice Member rank as (highest tier index + 1); 0 = never activated. Rank never decreases.
    mapping(address => uint8) public rankPlus1;
    /// @notice Activations per member per tier index (0..5). Bounds the 5-cycle limit (BD exempt).
    mapping(address => mapping(uint256 => uint256)) public cycleCount;
    /// @notice Remaining global income cap (countdown). +2x entry per activation; drawn down by every
    ///         reward. 0 = inactive (earns nothing until re-activated).
    mapping(address => uint256) public incomeCap;
    /// @notice Accrued product entitlement (USDT-value); redeemed to COCT in a later phase.
    mapping(address => uint256) public tokenBalance;
    /// @notice Accrued, not-yet-withdrawn reward income (USDT-value). EVERY earning stream — direct
    ///         referral, override, and the daily/direct/line passive claims — credits this ledger; no funds
    ///         move to the vault until `withdrawRewards`, where the `_stabilityBpsOf` fee is applied once.
    mapping(address => uint256) public rewardsBalance;

    /// @notice Own daily-passive mirrors (seeded at the member's own activation).
    mapping(address => PassiveData[]) public passive;
    /// @notice Direct-passive mirrors (seeded on a referral-L1 downline's activation).
    mapping(address => PassiveData[]) public directPassive;
    /// @notice Line-income mirrors (seeded on a line-tree downline's activation).
    mapping(address => PassiveData[]) public lineIncome;

    /* ----------------------------- Records ----------------------------- */
    mapping(address => uint256) public directReferralTotal;
    mapping(address => uint256) public overrideTotal;
    mapping(address => uint256) public dailyPassiveTotal;
    mapping(address => uint256) public directPassiveTotal;
    mapping(address => uint256) public lineIncomeTotal;

    /* ------------------------------ User id ---------------------------- */
    /// @notice Sequential member id, assigned from an INTERNAL counter (`lastUserId`), NOT accounts.totalUsers.
    ///         Auto-assigned on register (++lastUserId); an admin can set/override via setUserId. 0 = unassigned.
    mapping(address => uint256) public userId;
    /// @notice Reverse lookup id => owner (for duplicate detection + lookup). address(0) = id free.
    mapping(uint256 => address) public userById;
    /// @notice Highest user id assigned so far — the monotonic counter for auto-assignment.
    uint256 public lastUserId;

    /* ------------------------------- Agent ----------------------------- */
    /// @notice Whether an address is a designated agent (network leader). Set by an admin via setAgent.
    mapping(address => bool) public agent;
    /// @notice Accrued agent reward (USDT-value) — the 5% allocated to the first agent up a downline's
    ///         referral tree on each activation. UNCAPPED (independent of incomeCap / rewardsBalance) and
    ///         claimed directly to the agent's wallet via claimAgentRewards.
    mapping(address => uint256) public agentRewards;

    /* ------------------------------- Pause ----------------------------- */
    bool public paused;

    /* ------------------------------- Events ---------------------------- */
    event Registered(address indexed user, address indexed sponsor);
    event Activated(address indexed user, uint256 indexed tier, uint256 amount, uint256 incomeCapAdded);
    event ProductAccrued(address indexed user, uint256 amount);
    event TokenClaimed(address indexed user, uint256 usdtValue, uint256 coctOut);
    event TokenSwapped(address indexed user, uint256 usdtIn, uint256 coctOut);
    event DepositSplit(address indexed user, uint256 opex, uint256 agent, uint256 overrideReserve, uint256 product, uint256 pool, uint256 toLp);
    event DirectReferralPaid(address indexed earner, address indexed source, uint256 amount);
    event DailyPassiveSeeded(address indexed user, uint256 principal);
    event DirectPassiveSeeded(address indexed earner, address indexed source, uint256 principal);
    event LineIncomeSeeded(address indexed earner, address indexed source, uint256 level, uint256 principal);
    event OverridePaid(address indexed earner, address indexed source, uint256 amount);
    /// @notice Emitted when the first agent up a downline's referral tree is allocated the agent reward.
    event AgentPaid(address indexed agent, address indexed source, uint256 amount);
    /// @notice Emitted when an agent claims their accrued agent rewards to their wallet.
    event AgentRewardsClaimed(address indexed agent, uint256 amount);
    /// @notice Emitted when an address's agent flag is set/unset.
    event AgentSet(address indexed user, bool isAgent);
    /// @notice Emitted when a member's userId is assigned (on register) or set/overridden by an admin.
    event UserIdSet(address indexed user, uint256 indexed id);
    event DailyPassiveClaimed(address indexed user, uint256 amount);
    event DirectPassiveClaimed(address indexed user, uint256 amount);
    event LineIncomeClaimed(address indexed user, uint256 amount);
    /// @notice Emitted when a member withdraws accrued rewards: `gross` drawn from the ledger (pool-clamped),
    ///         `fee` = stability fee routed to the LP, `net` credited to the member's vault balance.
    event RewardsWithdrawn(address indexed user, uint256 gross, uint256 fee, uint256 net);
    event LiquidityRouted(uint256 usdtIn, uint256 liquidityAdded);
    event LiquidityRoutingFailed(uint256 usdtIn, string reason);
    event WalletsSet(address opex, address agent, address product, address liquidity);
    event SplitSet(uint256 opex, uint256 agent, uint256 overrideReserve, uint256 product, uint256 tokenLiquidity, uint256 lp);
    event EarningParamsSet(uint256 directReferralBps, uint256 directPassiveBps, uint256 lineIncomeBps, uint256 lineLevels, uint256 overrideMaxDepth, uint256 dailyPassiveBps, uint256 passiveCapBps, uint256 incomeCapBps);
    event TierTableSet(uint256[6] entry, uint256[6] overrideBps, uint256[6] stabilityBps);
    event BdStabilitySet(uint256[5] bps);
    event AssetsSet(address indexed assets);
    event LiquiditySet(address indexed manager);
    event PausedSet(bool paused);
    event ParamSet(string key, uint256 value);

    /* ------------------------------ Modifiers -------------------------- */
    modifier onlyAuth() {
        require(accounts.checkIsAdmin(msg.sender), "NOT_AUTH");
        _;
    }
    modifier whenNotPaused() {
        require(!paused, "PAUSED");
        _;
    }

    /* ----------------------------- Constructor ------------------------- */
    /// @notice Wire the hub to accounts + assets (+ optional LP manager). Wallets default to the deployer;
    ///         set the real ones with setWallets before launch.
    /// @param accountsAddr Deployed COCTAccounts (non-zero contract).
    /// @param assetsAddr Deployed COCTAssets vault (non-zero contract).
    /// @param liquidityAddr LP manager; may be address(0) to defer LP routing.
    constructor(address accountsAddr, address assetsAddr, address liquidityAddr) Ownable(msg.sender) {
        require(accountsAddr != address(0) && assetsAddr != address(0), "ZERO_DEP");
        require(accountsAddr.code.length > 0 && assetsAddr.code.length > 0, "NOT_CONTRACT");
        accounts = ICOCTAccounts(accountsAddr);
        assets = ICOCTAssets(assetsAddr);
        root = ICOCTAccounts(accountsAddr).root();
        liquidity = ILiquidity(liquidityAddr);

        opexWallet = msg.sender;
        agentWallet = msg.sender;
        productWallet = msg.sender;
        liquidityWallet = msg.sender;

        tierEntry = [uint256(20 ether), 50 ether, 100 ether, 500 ether, 1000 ether, 5000 ether];
        tierOverrideBps = [uint256(0), 100, 200, 300, 400, 500]; // [Silver 0, Gold 1, Plat 2, Diamond 3, Emerald 4, BD 5]%
        tierStabilityBps = [uint256(500), 600, 700, 800, 900, 0]; // index 5 (BD) uses bdStabilityBps
        bdStabilityBps = [uint256(1000), 1500, 2000, 2500, 3000];

        _requireValidSplit();
    }

    /* ============================== REGISTER =========================== */
    /// @notice Register into the COC referral tree under `sponsor` AND fund the entry: the lowest-tier amount
    ///         (`tierEntry[0]`, 20 USDT by default) is pulled from the caller into their Funding Wallet
    ///         (COCTAssets vault) — approve the vault for USDT first. Membership is EOA-only: smart-contract
    ///         wallets (Safe / ERC-4337) are blocked here, at signup. (Admins can still add non-EOA members
    ///         directly via accounts.addUser, which skips the entry.)
    /// @param sponsor An existing registered member to sponsor the caller.
    /// @dev Reverts CALLER_NOT_EOA; addUser guards not-registered / sponsor-exists / not-self / non-zero; the
    ///      entry pull reverts if the caller hasn't approved the vault or lacks the USDT.
    function register(address sponsor) external nonReentrant whenNotPaused {
        require(msg.sender == tx.origin, "CALLER_NOT_EOA");
        accounts.addUser(msg.sender, sponsor);
        userId[msg.sender] = ++lastUserId; // auto-assign the next sequential id (internal counter)
        userById[lastUserId] = msg.sender;
        emit UserIdSet(msg.sender, lastUserId);
        // Registration entry: pull the current lowest-tier amount into the member's Funding Wallet.
        uint256 entry = tierEntry[0];
        if (entry > 0) assets.depositFor(msg.sender, USDT, entry);
        emit Registered(msg.sender, sponsor);
    }

    /* ============================== ACTIVATE =========================== */
    /// @notice Activate an entry tier from your funded vault balance (deposit USDT to COCTAssets first).
    ///         Raises your income cap by 2x, accrues the product, splits the entry, and pays/seeds the five
    ///         earning streams up the trees.
    /// @param amount The entry amount; must equal a tier (20/50/100/500/1000/5000 USDT). Non-BD tiers are
    ///        limited to 5 cycles.
    function activate(uint256 amount) external nonReentrant whenNotPaused {
        address u = msg.sender;
        require(accounts.isUser(u), "NOT_REGISTERED");
        require(u != root, "ROOT_EXCLUDED");
        (bool found, uint256 tier) = tierIndexOf(amount);
        require(found, "INVALID_ENTRY");
        // Below Black Diamond rank: any tier is freely activatable (each capped at 5 cycles). Once you have
        // ever reached Black Diamond (rank BD → rankPlus1 == 6), all lower tiers lock — only BD may activate.
        if (rankPlus1[u] == 6) require(tier == 5, "BD_LOCKS_LOWER");
        if (tier != 5) require(cycleCount[u][tier] < 5, "CYCLE_LIMIT"); // BD (5) unlimited
        require(assets.balanceOf(u, USDT) >= amount, "INSUFFICIENT_FUNDS");

        // 1) Charge the entry (becomes vault surplus that backs the split credits).
        assets.debitBalance(u, USDT, amount);

        // 2) Cycle, rank (highest tier ever), income cap, product.
        cycleCount[u][tier] += 1;
        if (rankPlus1[u] < tier + 1) rankPlus1[u] = uint8(tier + 1);
        uint256 capAdd = (amount * incomeCapBps) / BPS; // 2x entry
        incomeCap[u] += capAdd;
        uint256 productAmt = (amount * productBps) / BPS;
        if (productAmt > 0) {
            tokenBalance[u] += productAmt;
            emit ProductAccrued(u, productAmt);
        }

        // 3) Deposit split (opex real USDT out; agent pool; override reserve + reward pool; routes LP). Runs BEFORE the
        //    instant payouts so the pool holds this entry's contribution when referral/override draw it.
        _splitDeposit(u, amount);

        // 4) Earning streams.
        (address sponsor, ) = accounts.getAffiliate(u);

        // 4a) Direct Referral 5% → referral-L1 sponsor, instant (capped, pool-funded).
        uint256 paidRef = _accrueReward(sponsor, (amount * directReferralBps) / BPS);
        if (paidRef > 0) {
            directReferralTotal[sponsor] += paidRef;
            emit DirectReferralPaid(sponsor, u, paidRef);
        }

        // 4b) Daily Passive — seed the member's OWN mirror (principal = entry, cap 200%).
        _seedPassive(passive[u], amount);
        emit DailyPassiveSeeded(u, amount);

        // 4c) Direct Passive 50% — seed a mirror for the referral-L1 sponsor (only if the sponsor is active).
        if (sponsor != address(0) && sponsor != root && incomeCap[sponsor] > 0) {
            uint256 dp = (amount * directPassiveBps) / BPS;
            if (dp > 0) {
                _seedPassive(directPassive[sponsor], dp);
                emit DirectPassiveSeeded(sponsor, u, dp);
            }
        }

        // 4d) Line Income 10%x10 — seed mirrors up the GLOBAL one-line.
        _seedLineIncome(u, amount);

        // 4e) Override — rank-differential, instant, up the referral tree.
        _payOverride(u, amount);

        // 4f) Agent — 5% to the first agent up the referral tree (uncapped leader incentive).
        _payAgent(u, amount);

        emit Activated(u, tier, amount, capAdd);
    }

    /* --------------------------- Deposit split ------------------------- */
    /// @dev Splits the entry. The entry was debited from the caller first (activate), so on a deposit-funded
    ///      activation the vault physically holds the entry's USDT to cover the real-token legs below.
    ///      - Opex 10% PAID OUT as real USDT to the external opex wallet (sweepSurplus — real-balance gated,
    ///        no denomination/cooldown/fee).
    ///      - Agent 5% credited to the DEDICATED agent pool (agentWallet); drained only at claimAgentRewards.
    ///      - Override 5% reserved into the reward pool (liquidityWallet) — part of the on-chain funding buffer.
    ///      - Product 1% credited to the DEDICATED product pool (productWallet) — funds the claimToken swap.
    ///      - Token-Liquidity 79% goes 40% → LP (when live) + 39% → reward pool, else 79% → reward pool.
    function _splitDeposit(address u, uint256 amount) internal {
        uint256 opexAmt = (amount * opexBps) / BPS;
        // Opex takes its cut as real USDT to its external wallet, drawn from the entry surplus.
        if (opexAmt > 0) assets.sweepSurplus(USDT, opexWallet, opexAmt);

        uint256 agentAmt = (amount * agentBps) / BPS;
        _credit(agentWallet, agentAmt);                 // dedicated agent pool

        uint256 overrideAmt = (amount * overrideBps) / BPS;
        _credit(liquidityWallet, overrideAmt);          // override reserve → reward pool

        uint256 productAmt = (amount * productBps) / BPS;
        _credit(productWallet, productAmt);             // dedicated product pool (funds claimToken swap)

        uint256 liq = (amount * tokenLiquidityBps) / BPS; // 79%
        uint256 toLp;
        uint256 toPool;
        if (_managerReady(liquidity)) {
            toLp = (amount * lpBps) / BPS; // 40%
            toPool = liq - toLp;           // remainder (39%) — kept in-vault as the reward pool
            _credit(liquidityWallet, toPool);
            if (toLp > 0) _routeLiquidity(toLp);
        } else {
            toPool = liq;                  // full 79% → reward pool
            _credit(liquidityWallet, toPool);
        }
        emit DepositSplit(u, opexAmt, agentAmt, overrideAmt, productAmt, toPool, toLp);
    }

    function _credit(address to, uint256 amount) internal {
        if (amount > 0) assets.creditBalance(to, USDT, amount);
    }

    /* --------------------------- Earning helpers ----------------------- */
    /// @dev Accrue `amount` of reward to `earner`, clamped to their remaining income cap. No funds move here —
    ///      it credits the `rewardsBalance` ledger and draws the cap; the pool is only touched at
    ///      `withdrawRewards`. Skips root / zero / inactive. Returns the amount actually accrued.
    function _accrueReward(address earner, uint256 amount) internal returns (uint256 accrued) {
        if (amount == 0 || earner == address(0) || earner == root) return 0;
        uint256 cap = incomeCap[earner];
        if (cap == 0) return 0;
        accrued = amount > cap ? cap : amount; // clamp to remaining cap
        incomeCap[earner] = cap - accrued;
        rewardsBalance[earner] += accrued;
    }

    /// @dev Seed a mirror tranche (no-op on zero principal or when the array is at maxPackages).
    function _seedPassive(PassiveData[] storage arr, uint256 principal) internal {
        if (principal == 0 || arr.length >= maxPackages) return;
        arr.push(PassiveData({
            amount: principal,
            startTime: block.timestamp,
            totalClaimed: 0,
            maxPayout: (principal * passiveCapBps) / BPS
        }));
    }

    /// @dev Seed Line Income mirrors up the global one-line, COMPRESSED: inactive uplines (incomeCap == 0) are
    ///      skipped WITHOUT consuming a level, so line income always reaches `lineLevels` ACTIVE uplines
    ///      (auto-compression). The raw walk is bounded by `overrideMaxDepth` steps to cap gas — the one-line
    ///      can be arbitrarily long, so without this a run of inactive members could walk the whole membership.
    function _seedLineIncome(address activator, uint256 amount) internal {
        uint256 principal = (amount * lineIncomeBps) / BPS;
        if (principal == 0) return;
        (address up, ) = accounts.line(activator);
        uint256 paid;   // count of ACTIVE uplines seeded (the compressed level)
        uint256 steps;  // raw line positions walked (gas bound)
        while (paid < lineLevels && steps < overrideMaxDepth) {
            if (up == address(0) || up == root) break;
            if (incomeCap[up] > 0) { // only active line-uplines earn — increment the level only when we pay
                paid++;
                _seedPassive(lineIncome[up], principal);
                emit LineIncomeSeeded(up, activator, paid, principal);
            }
            (up, ) = accounts.line(up);
            steps++;
        }
    }

    /// @dev Override: walk the referral tree up (depth-capped). Each ancestor U with child C on the path
    ///      earns max(0, U.override% − C.override%) × amount, instant + capped + pool-funded (telescoping
    ///      "higher-minus-lower" over group sales, accrued per activation).
    function _payOverride(address activator, uint256 amount) internal {
        uint256 childBps = _overrideBpsOf(activator);
        (address up, ) = accounts.getAffiliate(activator);
        for (uint256 i = 0; i < overrideMaxDepth; i++) {
            if (up == address(0) || up == root) break;
            uint256 upBps = _overrideBpsOf(up);
            if (upBps > childBps) {
                uint256 paid = _accrueReward(up, (amount * (upBps - childBps)) / BPS);
                if (paid > 0) {
                    overrideTotal[up] += paid;
                    emit OverridePaid(up, activator, paid);
                }
            }
            childBps = upBps;
            (up, ) = accounts.getAffiliate(up);
        }
    }

    /// @dev Agent reward: walk the referral tree up (reusing overrideMaxDepth) and allocate the FIRST agent
    ///      `agentBps` (5%) of the entry — a leader incentive OUTSIDE the income cap. Accrues to `agentRewards`
    ///      (no cap draw, no pool touch); funded from the pool at claimAgentRewards. Stops at the first agent.
    function _payAgent(address activator, uint256 amount) internal {
        uint256 pay = (amount * agentBps) / BPS;
        if (pay == 0) return;
        (address up, ) = accounts.getAffiliate(activator);
        for (uint256 i = 0; i < overrideMaxDepth; i++) {
            if (up == address(0) || up == root) break;
            if (agent[up]) {
                agentRewards[up] += pay;
                emit AgentPaid(up, activator, pay);
                break; // first agent only
            }
            (up, ) = accounts.getAffiliate(up);
        }
    }

    /* ============================== CLAIMS ============================= */
    /// @notice Realize accrued Daily Passive (your own mirrors) into your `rewardsBalance` ledger. NO fee is
    ///         taken here — the stability fee applies once at `withdrawRewards`. Draws your income cap by the
    ///         accrued amount. Cap-bounded only (no pool check; funds move at withdrawal).
    function claimDailyPassive() external nonReentrant whenNotPaused {
        address u = msg.sender;
        require(accounts.isUser(u), "NOT_REGISTERED");
        uint256 cap = incomeCap[u];
        require(cap > 0, "INACTIVE");
        uint256 gross = _accrue(passive[u], cap);
        require(gross > 0, "NOTHING");
        incomeCap[u] = cap - gross;
        rewardsBalance[u] += gross;
        dailyPassiveTotal[u] += gross;
        emit DailyPassiveClaimed(u, gross);
    }

    /// @notice Realize accrued Direct Passive (referral-L1 mirrors) into your `rewardsBalance` ledger.
    function claimDirectPassive() external nonReentrant whenNotPaused {
        uint256 paid = _claimMirror(directPassive[msg.sender]);
        directPassiveTotal[msg.sender] += paid;
        emit DirectPassiveClaimed(msg.sender, paid);
    }

    /// @notice Realize accrued Line Income (line-tree mirrors) into your `rewardsBalance` ledger.
    function claimLineIncome() external nonReentrant whenNotPaused {
        uint256 paid = _claimMirror(lineIncome[msg.sender]);
        lineIncomeTotal[msg.sender] += paid;
        emit LineIncomeClaimed(msg.sender, paid);
    }

    /// @notice Withdraw your FULL accrued `rewardsBalance` to your vault: the rank-based `_stabilityBpsOf` fee
    ///         is deducted as a haircut and the EXACT net is credited to your COCTAssets vault balance (then
    ///         withdrawable via assets.withdraw while the contract is funded). No pool clamp — the whole
    ///         accrued amount is credited; the vault is inflow-funded, so the actual cash-out is gated by the
    ///         real balance at `assets.withdraw` (INSUFFICIENT_BALANCE until funded).
    /// @dev nonReentrant + whenNotPaused. Reverts NOT_REGISTERED / NOTHING. The stability fee is a haircut
    ///      (net credited; the fee is simply not owed → improves vault health), not a live LP contribution.
    function withdrawRewards() external nonReentrant whenNotPaused {
        address u = msg.sender;
        require(accounts.isUser(u), "NOT_REGISTERED");
        uint256 gross = rewardsBalance[u];
        require(gross > 0, "NOTHING");
        rewardsBalance[u] = 0;

        uint256 fee = (gross * _stabilityBpsOf(u)) / BPS;
        uint256 net = gross - fee;

        // Push the EXACT net into the member's vault balance (unbacked credit — inflow-funded).
        if (net > 0) assets.creditBalance(u, USDT, net);
        emit RewardsWithdrawn(u, gross, fee, net);
    }

    /// @notice Claim your accrued agent rewards straight to your wallet (real USDT out). Pays only up to the
    ///         reward pool; any remainder stays accrued. Gated on the accrued balance, not the current agent
    ///         flag, so a demoted agent can still claim what they earned.
    /// @dev nonReentrant + whenNotPaused. Reverts NOTHING / POOL_EMPTY. Moves the pool balance to surplus
    ///      (debitBalance) then sweeps it to the caller's wallet (sweepSurplus) — no denomination/fee/cooldown.
    function claimAgentRewards() external nonReentrant whenNotPaused {
        address u = msg.sender;
        uint256 amount = agentRewards[u];
        require(amount > 0, "NOTHING");
        uint256 poolBal = assets.balanceOf(agentWallet, USDT);
        uint256 pay = amount < poolBal ? amount : poolBal;
        require(pay > 0, "POOL_EMPTY");
        agentRewards[u] = amount - pay;
        assets.debitBalance(agentWallet, USDT, pay);     // dedicated agent pool → vault surplus
        assets.sweepSurplus(USDT, u, pay);               // surplus → the agent's external wallet
        emit AgentRewardsClaimed(u, pay);
    }

    /// @notice Redeem your accrued product entitlement (`tokenBalance`, USDT-value) as COCT. PREFERRED path:
    ///         if the LP manager is live and the dedicated product pool holds enough USDT, swap that USDT →
    ///         COCT to you (market rate). FALLBACK: deliver COCT from the contract's reserve at `productRate`.
    ///         The product is separate from the five earning streams, so this does NOT touch your income cap.
    /// @dev Same shape as legacyprime `claimCashBack`/`withdrawToken` + `_deliverProduct`: zeroes the balance
    ///      (CEI), tries the swap (try/catch, funded from the productWallet pool, unspent USDT re-credited),
    ///      else the reserve. Reverts UNDELIVERABLE (rolling back, so your balance is kept) if neither pays.
    ///      nonReentrant + whenNotPaused. Reverts NOT_REGISTERED / NO_TOKEN_BALANCE.
    function claimToken() external nonReentrant whenNotPaused {
        address u = msg.sender;
        require(accounts.isUser(u), "NOT_REGISTERED");
        uint256 amount = tokenBalance[u];
        require(amount > 0, "NO_TOKEN_BALANCE");
        tokenBalance[u] = 0; // effect before interactions (CEI); a revert below rolls this back

        // 1) Preferred: swap USDT→COCT via the LP manager (funded from the dedicated product pool).
        if (_trySwapDeliver(u, amount)) return;

        // 2) Fallback: deliver COCT from the contract's reserve at productRate.
        uint256 coctOut = (amount * productRate) / 1e18;
        require(coctOut > 0 && IERC20(COCT).balanceOf(address(this)) >= coctOut, "UNDELIVERABLE");
        _safeTransfer(COCT, u, coctOut);
        emit TokenClaimed(u, amount, coctOut);
    }

    /// @dev Best-effort product delivery via a USDT→COCT swap, funded from the DEDICATED product pool
    ///      (productWallet). Returns false (delivering nothing) if the LP manager isn't ready or the product
    ///      pool can't fund `usdtAmount`. Otherwise it debits the pool → sweeps that USDT out of the vault →
    ///      swaps to `to` under try/catch; any unspent USDT (all of it on failure) is RE-CREDITED to the
    ///      product pool so the allocation is never orphaned. Returns true iff COCT was delivered.
    function _trySwapDeliver(address to, uint256 usdtAmount) internal returns (bool) {
        ILiquidity lp = liquidity;
        if (!_managerReady(lp)) return false;
        if (assets.balanceOf(productWallet, USDT) < usdtAmount) return false;

        assets.debitBalance(productWallet, USDT, usdtAmount); // product pool → vault surplus
        assets.sweepSurplus(USDT, address(this), usdtAmount); // surplus → this contract to swap
        _safeApprove(USDT, address(lp), usdtAmount);
        bool delivered;
        uint256 got;
        try lp.swapUSDTToCOCT(usdtAmount, uint24(liquiditySlippageBps), to, block.timestamp + 600) returns (uint256 out) {
            got = out;
            delivered = out > 0;
        } catch {
            delivered = false;
        }
        _safeApprove(USDT, address(lp), 0);

        // Reclaim any unspent USDT (all of it on failure; ~0 on a clean swap) back to the product pool.
        uint256 leftover = IERC20(USDT).balanceOf(address(this));
        if (leftover > 0) {
            _safeTransfer(USDT, address(assets), leftover);
            assets.creditBalance(productWallet, USDT, leftover); // return unspent USDT to the product pool
        }

        if (delivered) emit TokenSwapped(to, usdtAmount, got);
        return delivered;
    }

    /// @dev Shared mirror realization (direct passive / line income). Accrues up to the remaining income cap
    ///      into the caller's `rewardsBalance` ledger (no funds move until withdrawRewards).
    function _claimMirror(PassiveData[] storage arr) internal returns (uint256 paid) {
        address u = msg.sender;
        require(accounts.isUser(u), "NOT_REGISTERED");
        uint256 cap = incomeCap[u];
        require(cap > 0, "INACTIVE");
        paid = _accrue(arr, cap);
        require(paid > 0, "NOTHING");
        incomeCap[u] = cap - paid;
        rewardsBalance[u] += paid;
    }

    /// @dev Accrue mirror tranches up to `budget`, mutating each tranche's totalClaimed. Startime-based:
    ///      accruable = min(maxPayout, amount × dailyPassiveBps × daysElapsed / BPS); pending = accruable −
    ///      totalClaimed. Unpaid pending stays for the next claim (no forfeiture). Bounded by array length.
    function _accrue(PassiveData[] storage arr, uint256 budget) internal returns (uint256 paid) {
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; i++) {
            if (budget == 0) break;
            PassiveData storage p = arr[i];
            if (p.totalClaimed >= p.maxPayout) continue;
            uint256 daysElapsed = (block.timestamp - p.startTime) / oneDay;
            if (daysElapsed == 0) continue;
            uint256 accruable = (p.amount * dailyPassiveBps * daysElapsed) / BPS;
            if (accruable > p.maxPayout) accruable = p.maxPayout;
            if (accruable <= p.totalClaimed) continue;
            uint256 pending = accruable - p.totalClaimed;
            uint256 take = pending < budget ? pending : budget;
            p.totalClaimed += take;
            paid += take;
            budget -= take;
        }
    }

    /* ============================== VIEWS ============================= */
    /// @notice Total accrued-but-unclaimed amount across a member's tranche array (ignores cap/pool limits).
    function _pendingView(PassiveData[] storage arr) internal view returns (uint256 total) {
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; i++) {
            PassiveData storage p = arr[i];
            if (p.totalClaimed >= p.maxPayout) continue;
            uint256 daysElapsed = (block.timestamp - p.startTime) / oneDay;
            uint256 accruable = (p.amount * dailyPassiveBps * daysElapsed) / BPS;
            if (accruable > p.maxPayout) accruable = p.maxPayout;
            if (accruable > p.totalClaimed) total += accruable - p.totalClaimed;
        }
    }

    /// @notice Aggregated dashboard snapshot for a member.
    struct UserView {
        bool registered;
        bool activated;
        uint8 rank;            // 0..5 (valid when activated)
        uint256 incomeCap;     // remaining
        uint256 tokenBalance;
        uint256 rewardsBalance; // accrued, withdrawable via withdrawRewards (fee applied then)
        uint256 pendingDaily;
        uint256 pendingDirect;
        uint256 pendingLine;
    }

    /// @notice One-call snapshot for a frontend.
    function getUser(address u) external view returns (UserView memory v) {
        v.registered = accounts.isUser(u);
        v.activated = rankPlus1[u] != 0;
        v.rank = v.activated ? rankPlus1[u] - 1 : 0;
        v.incomeCap = incomeCap[u];
        v.tokenBalance = tokenBalance[u];
        v.rewardsBalance = rewardsBalance[u];
        v.pendingDaily = _pendingView(passive[u]);
        v.pendingDirect = _pendingView(directPassive[u]);
        v.pendingLine = _pendingView(lineIncome[u]);
    }

    /// @notice Pending accrued amounts for each stream (cap/pool not applied).
    function pendingRewards(address u) external view returns (uint256 daily, uint256 direct, uint256 line) {
        return (_pendingView(passive[u]), _pendingView(directPassive[u]), _pendingView(lineIncome[u]));
    }

    /// @notice A member's per-tier cycle counts [Silver..Black Diamond].
    function getCycles(address u) external view returns (uint256[6] memory c) {
        for (uint256 i = 0; i < 6; i++) c[i] = cycleCount[u][i];
    }

    /// @notice Whether `user` is currently active (has remaining income cap).
    function isActive(address user) external view returns (bool) {
        return incomeCap[user] > 0;
    }

    /// @notice The tier index (0..5) for an entry `amount`, and whether it matched a tier.
    function tierIndexOf(uint256 amount) public view returns (bool found, uint256 index) {
        for (uint256 i = 0; i < 6; i++) {
            if (tierEntry[i] == amount) return (true, i);
        }
        return (false, 0);
    }

    /// @notice The daily-passive stability fee (bps) applied to `user` on claim (rank-based; BD cycle-scaled).
    function stabilityBpsOf(address user) external view returns (uint256) {
        return _stabilityBpsOf(user);
    }

    /* ---------------------------- Internal rank ------------------------ */
    function _rankTierOf(address u) internal view returns (bool activated, uint256 tierIdx) {
        uint8 rp = rankPlus1[u];
        if (rp == 0) return (false, 0);
        return (true, rp - 1);
    }

    function _overrideBpsOf(address u) internal view returns (uint256) {
        (bool act, uint256 idx) = _rankTierOf(u);
        return act ? tierOverrideBps[idx] : 0;
    }

    function _stabilityBpsOf(address u) internal view returns (uint256) {
        (bool act, uint256 idx) = _rankTierOf(u);
        if (!act) return 0;
        if (idx == 5) {
            uint256 c = cycleCount[u][5];      // BD activations; rank BD ⇒ c >= 1
            uint256 k = c == 0 ? 0 : c - 1;
            if (k > 4) k = 4;
            return bdStabilityBps[k];
        }
        return tierStabilityBps[idx];
    }

    /* ============================== ADMIN ============================= */
    /// @notice Set the four wallets (all non-zero, all distinct). opexWallet receives the 10% opex cut as real
    ///         USDT; agentWallet is the dedicated agent pool; productWallet is the dedicated product pool
    ///         (funds the claimToken swap); liquidityWallet is the reward/payout pool. The stability fee is
    ///         routed to the LP (not a wallet), so there is no stability wallet.
    function setWallets(address opex_, address agent_, address product_, address liquidity_) external onlyAuth {
        require(opex_ != address(0) && agent_ != address(0) && product_ != address(0) && liquidity_ != address(0), "ZERO_WALLET");
        require(
            opex_ != agent_ && opex_ != product_ && opex_ != liquidity_
            && agent_ != product_ && agent_ != liquidity_ && product_ != liquidity_,
            "WALLETS_NOT_DISTINCT"
        );
        opexWallet = opex_;
        agentWallet = agent_;
        productWallet = product_;
        liquidityWallet = liquidity_;
        emit WalletsSet(opex_, agent_, product_, liquidity_);
    }

    /// @notice Set the deposit split (opex+agent+override+product+tokenLiquidity must sum to 100%; lp ≤ tokenLiquidity).
    ///         `agent_` sets `agentBps` (both the agent-pool reserve AND the per-agent payout rate); `product_`
    ///         sets `productBps` (both the product-pool reserve AND the product-entitlement accrual rate), so
    ///         each pool always funds its own payouts.
    function setSplit(uint256 opex_, uint256 agent_, uint256 override_, uint256 product_, uint256 tokenLiquidity_, uint256 lp_) external onlyAuth {
        opexBps = opex_;
        agentBps = agent_;
        overrideBps = override_;
        productBps = product_;
        tokenLiquidityBps = tokenLiquidity_;
        lpBps = lp_;
        _requireValidSplit();
        emit SplitSet(opex_, agent_, override_, product_, tokenLiquidity_, lp_);
    }

    /// @notice Set the earning parameters (all bps unless noted). Bounds keep the cap/passive math sane.
    function setEarningParams(
        uint256 directReferralBps_,
        uint256 directPassiveBps_,
        uint256 lineIncomeBps_,
        uint256 lineLevels_,
        uint256 overrideMaxDepth_,
        uint256 dailyPassiveBps_,
        uint256 passiveCapBps_,
        uint256 incomeCapBps_
    ) external onlyAuth {
        require(lineLevels_ >= 1 && lineLevels_ <= 50, "BAD_LEVELS");
        require(overrideMaxDepth_ >= 1 && overrideMaxDepth_ <= 500, "BAD_DEPTH");
        require(dailyPassiveBps_ >= 1 && dailyPassiveBps_ <= BPS, "BAD_DAILY");
        require(passiveCapBps_ >= BPS && passiveCapBps_ <= 1_000_000, "BAD_CAP");
        require(incomeCapBps_ >= BPS && incomeCapBps_ <= 1_000_000, "BAD_INCOME_CAP");
        directReferralBps = directReferralBps_;
        directPassiveBps = directPassiveBps_;
        lineIncomeBps = lineIncomeBps_;
        lineLevels = lineLevels_;
        overrideMaxDepth = overrideMaxDepth_;
        dailyPassiveBps = dailyPassiveBps_;
        passiveCapBps = passiveCapBps_;
        incomeCapBps = incomeCapBps_;
        emit EarningParamsSet(directReferralBps_, directPassiveBps_, lineIncomeBps_, lineLevels_, overrideMaxDepth_, dailyPassiveBps_, passiveCapBps_, incomeCapBps_);
    }

    /// @notice Set the tier table (entries strictly increasing; each bps ≤ 100%).
    function setTierTable(uint256[6] calldata entry, uint256[6] calldata overrideBps_, uint256[6] calldata stabilityBps) external onlyAuth {
        for (uint256 i = 0; i < 6; i++) {
            require(entry[i] > 0, "ZERO_ENTRY");
            if (i > 0) require(entry[i] > entry[i - 1], "NOT_INCREASING");
            require(overrideBps_[i] <= BPS && stabilityBps[i] <= BPS, "BPS_TOO_HIGH");
        }
        tierEntry = entry;
        tierOverrideBps = overrideBps_;
        tierStabilityBps = stabilityBps;
        emit TierTableSet(entry, overrideBps_, stabilityBps);
    }

    /// @notice Set the Black Diamond cycle-scaled stability fees (each ≤ 100%).
    function setBdStability(uint256[5] calldata bps) external onlyAuth {
        for (uint256 i = 0; i < 5; i++) require(bps[i] <= BPS, "BPS_TOO_HIGH");
        bdStabilityBps = bps;
        emit BdStabilitySet(bps);
    }

    /// @notice Repoint the assets vault. AUTH-ONLY. DANGER: the vault custodies ALL member funds — repointing
    ///         to a different vault strands the balances held in the old one and, if pointed at a malicious
    ///         vault, enables draining. Use ONLY for a deliberate, audited migration behind the multisig.
    function setAssets(address assetsAddr) external onlyAuth {
        require(assetsAddr != address(0), "ZERO_ASSETS");
        require(assetsAddr.code.length > 0, "NOT_CONTRACT"); // guard against repointing at an EOA/typo
        assets = ICOCTAssets(assetsAddr);
        emit AssetsSet(assetsAddr);
    }

    /// @notice Set the LP manager (address(0) disables routing → the 80% all goes to the reward pool).
    function setLiquidity(address manager) external onlyAuth {
        liquidity = ILiquidity(manager);
        emit LiquiditySet(manager);
    }

    /// @notice Set the LP-routing max slippage (bps, ≤ 50%).
    function setLiquiditySlippage(uint256 bps) external onlyAuth {
        require(bps <= 5000, "SLIPPAGE_TOO_HIGH");
        liquiditySlippageBps = bps;
        emit ParamSet("liquiditySlippageBps", bps);
    }

    /// @notice Flag/unflag `user` as an agent (network leader eligible for the agent reward). Auth-gated.
    function setAgent(address user, bool isAgent) external onlyAuth {
        agent[user] = isAgent;
        emit AgentSet(user, isAgent);
    }

    /// @notice Set or auto-assign a member's userId. Auth-gated.
    /// @param user The member whose id to set.
    /// @param _id The id to assign; pass 0 to auto-assign the next sequential id (++lastUserId). A non-zero id
    ///        must not already belong to a different member (ID_TAKEN). Does NOT use accounts.totalUsers().
    function setUserId(address user, uint256 _id) external onlyAuth {
        uint256 old = userId[user];
        if (_id == 0) {
            _id = ++lastUserId; // auto-assign the next number
        } else {
            require(userById[_id] == address(0) || userById[_id] == user, "ID_TAKEN");
            if (_id > lastUserId) lastUserId = _id; // keep the counter ahead so auto-assign won't collide
        }
        if (old != 0 && old != _id) userById[old] = address(0); // free the previous id
        userId[user] = _id;
        userById[_id] = user;
        emit UserIdSet(user, _id);
    }

    /// @notice Set the per-array tranche cap (1..1000).
    function setMaxPackages(uint256 n) external onlyAuth {
        require(n >= 1 && n <= 1000, "BAD_MAX");
        maxPackages = n;
        emit ParamSet("maxPackages", n);
    }

    /// @notice Set the product redemption rate — COCT per 1 USDT of accrued product (1e18-scaled).
    /// @param rate The new rate (> 0, ≤ 1e30). Default 100e18 (1 USDT-value → 100 COCT at $0.01).
    function setProductRate(uint256 rate) external onlyAuth {
        require(rate > 0 && rate <= 1e30, "BAD_RATE");
        productRate = rate;
        emit ParamSet("productRate", rate);
    }

    /// @notice Set the accrual period in seconds (1s..1d; test hook).
    function setOneDay(uint256 secs) external onlyAuth {
        require(secs >= 1 && secs <= 1 days, "BAD_ONE_DAY");
        oneDay = secs;
        emit ParamSet("oneDay", secs);
    }

    /// @notice Pause/unpause register + activate + claims.
    function setPaused(bool _paused) external onlyAuth {
        paused = _paused;
        emit PausedSet(_paused);
    }

    function _requireValidSplit() internal view {
        require(opexBps + agentBps + overrideBps + productBps + tokenLiquidityBps == BPS, "BAD_SPLIT");
        require(lpBps <= tokenLiquidityBps, "LP_GT_LIQUIDITY");
    }

    /* -------------------------- LP routing helpers --------------------- */
    /// @dev Route `amount` USDT to the LP manager. The manager call is best-effort (try/catch, leftover
    ///      re-pooled), BUT the initial `sweepSurplus` is real-balance-gated: if the vault physically lacks
    ///      `amount` (over-committed), this REVERTS and bubbles up to `activate`. Only an entry backed by a
    ///      fresh real deposit is guaranteed to have the tokens for this sweep; activating from an unbacked
    ///      (reward-credited) balance while the vault is under-funded will revert here.
    function _routeLiquidity(uint256 amount) internal {
        ILiquidity lp = liquidity;
        assets.sweepSurplus(USDT, address(this), amount);
        _safeApprove(USDT, address(lp), amount);
        try lp.addLiquidityUSDT(amount, uint24(liquiditySlippageBps), block.timestamp + 600) returns (uint256 lpAdded) {
            if (lpAdded > 0) emit LiquidityRouted(amount, lpAdded);
            else emit LiquidityRoutingFailed(amount, "returned zero");
        } catch Error(string memory reason) {
            emit LiquidityRoutingFailed(amount, reason);
        } catch {
            emit LiquidityRoutingFailed(amount, "unknown");
        }
        _safeApprove(USDT, address(lp), 0);
        uint256 leftover = IERC20(USDT).balanceOf(address(this));
        if (leftover > 0) {
            _safeTransfer(USDT, address(assets), leftover);
            assets.creditBalance(liquidityWallet, USDT, leftover); // return unrouted USDT to the reward pool
        }
    }

    /// @dev Is the LP manager present, coded, and holding an initialized position?
    function _managerReady(ILiquidity lp) internal view returns (bool) {
        if (address(lp) == address(0) || address(lp).code.length == 0) return false;
        try lp.TOKENID() returns (uint256 id) {
            return id != 0;
        } catch {
            return false;
        }
    }

    function _safeApprove(address token, address spender, uint256 value) private {
        require(token.code.length > 0, "NOT_CONTRACT");
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, value));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        require(token.code.length > 0, "NOT_CONTRACT");
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }
}
