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
 * splits 100% (10 admin / 5 marketing / 5 leaders / 80 token-liquidity), accrues a rank-% COCT product,
 * and raises a single 200% income cap by 2x the entry. Five earning streams — Direct Referral (5%),
 * Daily Passive (1%/day own), Direct Passive (50% referral-L1 mirror), Line Income (10%x10 line-tree
 * mirror), and rank-differential Override — all draw down that income cap and are PAID FROM the reward
 * pool (the liquidityWallet vault balance) via assets.balanceTransfer. Inflow-funded by design.
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
    function balanceTransfer(address from, address to, address token, uint256 amount) external;
    function sweepSurplus(address token, address to, uint256 amount) external;
    function surplus(address token) external view returns (uint256);
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
/// @dev Self-contained (inlined ReentrancyGuard). All rewards are paid from the reward pool (the
///      liquidityWallet vault balance) via balanceTransfer, and each draws the payee's single 200% income
///      cap. See docs/REWARDS.md.
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
    ICOCTAssets public immutable assets;
    /// @notice The structural root anchor (cached from accounts) — excluded from all earning streams.
    address public immutable root;
    /// @notice External COCTLiquidity manager. address(0) / uninitialized disables LP routing.
    ILiquidity public liquidity;
    /// @notice Max slippage (bps) passed to the LP manager. Default 3%.
    uint256 public liquiditySlippageBps = 300;

    /* ------------------------------- Wallets --------------------------- */
    /// @notice Receives the 10% Admin allocation (vault balance).
    address public adminWallet;
    /// @notice Receives the 5% Marketing allocation.
    address public marketingWallet;
    /// @notice Receives the 5% Leaders Group Sales allocation.
    address public leadersWallet;
    /// @notice THE REWARD POOL — receives the retained Token-Liquidity share (40% when LP is live, else
    ///         80%). All earnings are paid FROM this account's vault balance via balanceTransfer.
    address public liquidityWallet;
    /// @notice Receives the COC Stability Contribution fees taken on daily-passive claims.
    address public stabilityWallet;

    /* --------------------------- Split (bps of entry) ------------------ */
    uint256 public adminBps = 1_000;          // 10%
    uint256 public marketingBps = 500;        // 5%
    uint256 public leadersBps = 500;          // 5%
    uint256 public tokenLiquidityBps = 8_000; // 80% (admin+marketing+leaders+tokenLiquidity == BPS)
    uint256 public lpBps = 4_000;             // of the entry: portion of the 80% routed to the LP (rest → pool)

    /* --------------------------- Earning params ------------------------ */
    uint256 public directReferralBps = 500;   // 5% to the referral-L1 sponsor, instant
    uint256 public directPassiveBps = 5_000;  // 50% referral-L1 mirror principal
    uint256 public lineIncomeBps = 1_000;     // 10% per line level mirror principal
    uint256 public lineLevels = 10;           // line-tree depth for Line Income
    uint256 public overrideMaxDepth = 100;    // referral-tree walk cap for Override
    uint256 public dailyPassiveBps = 100;     // 1%/day accrual on every mirror
    uint256 public passiveCapBps = 20_000;    // 200% max payout per mirror tranche
    uint256 public incomeCapBps = 20_000;     // +200% (2x entry) added to the income cap per activation
    uint256 public oneDay = 1 days;           // accrual period (configurable for testing)
    uint256 public maxPackages = 200;         // per-array tranche cap (bounds claim loops)
    uint256 public productRate = 100 ether;   // COCT delivered per 1 USDT of accrued product (1e18-scaled):
                                              // coctOut = tokenBalance × productRate / 1e18. Default 100 (COCT @ $0.01).

    /* ------------------------------- Tiers ----------------------------- */
    /// @notice Entry amount per tier: [Silver, Gold, Platinum, Diamond, Emerald, Black Diamond].
    uint256[6] public tierEntry;
    /// @notice Product COCT % (bps) per tier: [0,1,2,3,4,5]%.
    uint256[6] public tierProductBps;
    /// @notice Override % (bps) per tier: [0,0,2,3,4,5]%.
    uint256[6] public tierOverrideBps;
    /// @notice Daily-passive stability fee (bps) per tier for Silver..Emerald; Black Diamond (index 5) uses
    ///         bdStabilityBps instead (cycle-scaled).
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

    /* ------------------------------- Pause ----------------------------- */
    bool public paused;

    /* ------------------------------- Events ---------------------------- */
    event Registered(address indexed user, address indexed sponsor);
    event Activated(address indexed user, uint256 indexed tier, uint256 amount, uint256 incomeCapAdded);
    event ProductAccrued(address indexed user, uint256 amount);
    event TokenClaimed(address indexed user, uint256 usdtValue, uint256 coctOut);
    event TokenSwapped(address indexed user, uint256 usdtIn, uint256 coctOut);
    event DepositSplit(address indexed user, uint256 admin, uint256 marketing, uint256 leaders, uint256 pool, uint256 toLp);
    event DirectReferralPaid(address indexed earner, address indexed source, uint256 amount);
    event DailyPassiveSeeded(address indexed user, uint256 principal);
    event DirectPassiveSeeded(address indexed earner, address indexed source, uint256 principal);
    event LineIncomeSeeded(address indexed earner, address indexed source, uint256 level, uint256 principal);
    event OverridePaid(address indexed earner, address indexed source, uint256 amount);
    event DailyPassiveClaimed(address indexed user, uint256 gross, uint256 fee, uint256 net);
    event DirectPassiveClaimed(address indexed user, uint256 amount);
    event LineIncomeClaimed(address indexed user, uint256 amount);
    event LiquidityRouted(uint256 usdtIn, uint256 liquidityAdded);
    event LiquidityRoutingFailed(uint256 usdtIn, string reason);
    event WalletsSet(address admin, address marketing, address leaders, address liquidity, address stability);
    event SplitSet(uint256 admin, uint256 marketing, uint256 leaders, uint256 tokenLiquidity, uint256 lp);
    event EarningParamsSet(uint256 directReferralBps, uint256 directPassiveBps, uint256 lineIncomeBps, uint256 lineLevels, uint256 overrideMaxDepth, uint256 dailyPassiveBps, uint256 passiveCapBps, uint256 incomeCapBps);
    event TierTableSet(uint256[6] entry, uint256[6] productBps, uint256[6] overrideBps, uint256[6] stabilityBps);
    event BdStabilitySet(uint256[5] bps);
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

        adminWallet = msg.sender;
        marketingWallet = msg.sender;
        leadersWallet = msg.sender;
        liquidityWallet = msg.sender;
        stabilityWallet = msg.sender;

        tierEntry = [uint256(20 ether), 50 ether, 100 ether, 500 ether, 1000 ether, 5000 ether];
        tierProductBps = [uint256(0), 100, 200, 300, 400, 500];
        tierOverrideBps = [uint256(0), 0, 200, 300, 400, 500];
        tierStabilityBps = [uint256(500), 600, 700, 800, 900, 0]; // index 5 (BD) uses bdStabilityBps
        bdStabilityBps = [uint256(1000), 1500, 2000, 2500, 3000];

        _requireValidSplit();
    }

    /* ============================== REGISTER =========================== */
    /// @notice Register into the COC referral tree under `sponsor`. Free; the entry is paid at `activate`.
    /// @param sponsor An existing registered member to sponsor the caller.
    function register(address sponsor) external whenNotPaused {
        accounts.addUser(msg.sender, sponsor); // enforces not-registered / sponsor-exists / not-self / non-zero
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
        if (tier != 5) require(cycleCount[u][tier] < 5, "CYCLE_LIMIT"); // BD (5) unlimited
        require(assets.balanceOf(u, USDT) >= amount, "INSUFFICIENT_FUNDS");

        // 1) Charge the entry (becomes vault surplus that backs the split credits).
        assets.debitBalance(u, USDT, amount);

        // 2) Cycle, rank (highest tier ever), income cap, product.
        cycleCount[u][tier] += 1;
        if (rankPlus1[u] < tier + 1) rankPlus1[u] = uint8(tier + 1);
        uint256 capAdd = (amount * incomeCapBps) / BPS; // 2x entry
        incomeCap[u] += capAdd;
        uint256 productAmt = (amount * tierProductBps[tier]) / BPS;
        if (productAmt > 0) {
            tokenBalance[u] += productAmt;
            emit ProductAccrued(u, productAmt);
        }

        // 3) Deposit split (credits admin/marketing/leaders + the reward pool; routes LP). Runs BEFORE the
        //    instant payouts so the pool holds this entry's contribution when referral/override draw it.
        _splitDeposit(u, amount);

        // 4) Earning streams.
        (address sponsor, ) = accounts.getAffiliate(u);

        // 4a) Direct Referral 5% → referral-L1 sponsor, instant (capped, pool-funded).
        uint256 paidRef = _payCapped(sponsor, (amount * directReferralBps) / BPS);
        if (paidRef > 0) {
            directReferralTotal[sponsor] += paidRef;
            emit DirectReferralPaid(sponsor, u, paidRef);
        }

        // 4b) Daily Passive — seed the member's OWN mirror (principal = entry, cap 200%).
        _seedPassive(passive[u], amount);
        emit DailyPassiveSeeded(u, amount);

        // 4c) Direct Passive 50% — seed a mirror for the referral-L1 sponsor.
        if (sponsor != address(0) && sponsor != root) {
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

        emit Activated(u, tier, amount, capAdd);
    }

    /* --------------------------- Deposit split ------------------------- */
    /// @dev Splits the entry: admin/marketing/leaders credited (backed by the entry surplus); the
    ///      Token-Liquidity 80% goes 40% → LP (when live) + 40% → reward pool, else 80% → reward pool.
    function _splitDeposit(address u, uint256 amount) internal {
        uint256 adminAmt = (amount * adminBps) / BPS;
        uint256 mktgAmt = (amount * marketingBps) / BPS;
        uint256 leadersAmt = (amount * leadersBps) / BPS;
        _credit(adminWallet, adminAmt);
        _credit(marketingWallet, mktgAmt);
        _credit(leadersWallet, leadersAmt);

        uint256 liq = (amount * tokenLiquidityBps) / BPS; // 80%
        uint256 toLp;
        uint256 toPool;
        if (_managerReady(liquidity)) {
            toLp = (amount * lpBps) / BPS; // 40%
            toPool = liq - toLp;           // remainder (40%) — kept in-vault as the reward pool
            _credit(liquidityWallet, toPool);
            if (toLp > 0) _routeLiquidity(toLp);
        } else {
            toPool = liq;                  // full 80% → reward pool
            _credit(liquidityWallet, toPool);
        }
        emit DepositSplit(u, adminAmt, mktgAmt, leadersAmt, toPool, toLp);
    }

    function _credit(address to, uint256 amount) internal {
        if (amount > 0) assets.creditBalance(to, USDT, amount);
    }

    /* --------------------------- Earning helpers ----------------------- */
    /// @dev Pay `amount` to `earner` from the reward pool, clamped to their remaining income cap AND the
    ///      pool balance (never reverts on a dry pool — pays what is available). Draws the cap by the amount
    ///      paid. Skips root / zero / inactive. Returns the amount actually paid.
    function _payCapped(address earner, uint256 amount) internal returns (uint256 paid) {
        if (amount == 0 || earner == address(0) || earner == root) return 0;
        uint256 cap = incomeCap[earner];
        if (cap == 0) return 0;
        uint256 poolBal = assets.balanceOf(liquidityWallet, USDT);
        paid = amount;
        if (paid > cap) paid = cap;
        if (paid > poolBal) paid = poolBal;
        if (paid == 0) return 0;
        incomeCap[earner] = cap - paid;
        assets.balanceTransfer(liquidityWallet, earner, USDT, paid);
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

    /// @dev Seed Line Income mirrors up the global one-line (lineLevels deep, root-terminated).
    function _seedLineIncome(address activator, uint256 amount) internal {
        uint256 principal = (amount * lineIncomeBps) / BPS;
        if (principal == 0) return;
        (address up, ) = accounts.line(activator);
        for (uint256 lvl = 1; lvl <= lineLevels; lvl++) {
            if (up == address(0) || up == root) break;
            _seedPassive(lineIncome[up], principal);
            emit LineIncomeSeeded(up, activator, lvl, principal);
            (up, ) = accounts.line(up);
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
                uint256 paid = _payCapped(up, (amount * (upBps - childBps)) / BPS);
                if (paid > 0) {
                    overrideTotal[up] += paid;
                    emit OverridePaid(up, activator, paid);
                }
            }
            childBps = upBps;
            (up, ) = accounts.getAffiliate(up);
        }
    }

    /* ============================== CLAIMS ============================= */
    /// @notice Claim accrued Daily Passive (your own mirrors). A rank-based COC Stability Contribution fee
    ///         is deducted and sent to stabilityWallet; the net is credited to your vault balance. Draws
    ///         your income cap by the gross. Pays only up to the reward pool.
    function claimDailyPassive() external nonReentrant whenNotPaused {
        address u = msg.sender;
        require(accounts.isUser(u), "NOT_REGISTERED");
        uint256 cap = incomeCap[u];
        require(cap > 0, "INACTIVE");
        uint256 poolBal = assets.balanceOf(liquidityWallet, USDT);
        uint256 budget = cap < poolBal ? cap : poolBal;
        require(budget > 0, "POOL_EMPTY");
        uint256 gross = _accrue(passive[u], budget);
        require(gross > 0, "NOTHING");
        incomeCap[u] = cap - gross;
        uint256 fee = (gross * _stabilityBpsOf(u)) / BPS;
        uint256 net = gross - fee;
        if (net > 0) assets.balanceTransfer(liquidityWallet, u, USDT, net);
        if (fee > 0) assets.balanceTransfer(liquidityWallet, stabilityWallet, USDT, fee);
        dailyPassiveTotal[u] += gross;
        emit DailyPassiveClaimed(u, gross, fee, net);
    }

    /// @notice Claim accrued Direct Passive (referral-L1 mirrors). Draws your income cap; no stability fee.
    function claimDirectPassive() external nonReentrant whenNotPaused {
        uint256 paid = _claimMirror(directPassive[msg.sender]);
        directPassiveTotal[msg.sender] += paid;
        emit DirectPassiveClaimed(msg.sender, paid);
    }

    /// @notice Claim accrued Line Income (line-tree mirrors). Draws your income cap; no stability fee.
    function claimLineIncome() external nonReentrant whenNotPaused {
        uint256 paid = _claimMirror(lineIncome[msg.sender]);
        lineIncomeTotal[msg.sender] += paid;
        emit LineIncomeClaimed(msg.sender, paid);
    }

    /// @notice Redeem your accrued product entitlement (`tokenBalance`, USDT-value) as COCT. PREFERRED path:
    ///         if the LP manager is live and the vault holds enough USDT surplus, swap that USDT → COCT to
    ///         you (market rate). FALLBACK: deliver COCT from the contract's reserve at `productRate`. The
    ///         product is separate from the five earning streams, so this does NOT touch your income cap.
    /// @dev Same shape as legacyprime `claimCashBack`/`withdrawToken` + `_deliverProduct`: zeroes the balance
    ///      (CEI), tries the swap (try/catch, funded via assets.sweepSurplus, no USDT left stranded), else the
    ///      reserve. Reverts UNDELIVERABLE (rolling back, so your balance is kept) if neither path can pay.
    ///      nonReentrant + whenNotPaused. Reverts NOT_REGISTERED / NO_TOKEN_BALANCE.
    function claimToken() external nonReentrant whenNotPaused {
        address u = msg.sender;
        require(accounts.isUser(u), "NOT_REGISTERED");
        uint256 amount = tokenBalance[u];
        require(amount > 0, "NO_TOKEN_BALANCE");
        tokenBalance[u] = 0; // effect before interactions (CEI); a revert below rolls this back

        // 1) Preferred: swap USDT→COCT via the LP manager (funded from the vault's USDT surplus).
        if (_trySwapDeliver(u, amount)) return;

        // 2) Fallback: deliver COCT from the contract's reserve at productRate.
        uint256 coctOut = (amount * productRate) / 1e18;
        require(coctOut > 0 && IERC20(COCT).balanceOf(address(this)) >= coctOut, "UNDELIVERABLE");
        _safeTransfer(COCT, u, coctOut);
        emit TokenClaimed(u, amount, coctOut);
    }

    /// @dev Best-effort product delivery via a USDT→COCT swap. Returns false (delivering nothing) if the LP
    ///      manager isn't ready or the vault's USDT surplus can't fund `usdtAmount`. Otherwise it sweeps that
    ///      USDT out of the vault, approves the manager, and swaps to `to` under try/catch; any unspent USDT
    ///      (all of it on failure) is returned to the vault so nothing is stranded. Returns true iff COCT was
    ///      delivered.
    function _trySwapDeliver(address to, uint256 usdtAmount) internal returns (bool) {
        ILiquidity lp = liquidity;
        if (!_managerReady(lp)) return false;
        if (assets.surplus(USDT) < usdtAmount) return false;

        assets.sweepSurplus(USDT, address(this), usdtAmount); // pull real USDT out of the vault surplus
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

        // Reclaim any unspent USDT back to the vault (all of it on failure; ~0 on a clean swap).
        uint256 leftover = IERC20(USDT).balanceOf(address(this));
        if (leftover > 0) _safeTransfer(USDT, address(assets), leftover);

        if (delivered) emit TokenSwapped(to, usdtAmount, got);
        return delivered;
    }

    /// @dev Shared no-fee mirror claim (direct passive / line income). Pays min(cap, pool) to the caller.
    function _claimMirror(PassiveData[] storage arr) internal returns (uint256 paid) {
        address u = msg.sender;
        require(accounts.isUser(u), "NOT_REGISTERED");
        uint256 cap = incomeCap[u];
        require(cap > 0, "INACTIVE");
        uint256 poolBal = assets.balanceOf(liquidityWallet, USDT);
        uint256 budget = cap < poolBal ? cap : poolBal;
        require(budget > 0, "POOL_EMPTY");
        paid = _accrue(arr, budget);
        require(paid > 0, "NOTHING");
        incomeCap[u] = cap - paid;
        assets.balanceTransfer(liquidityWallet, u, USDT, paid);
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
        uint8 rank;          // 0..5 (valid when activated)
        uint256 incomeCap;   // remaining
        uint256 tokenBalance;
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
    /// @notice Set the five wallets (all non-zero). liquidityWallet is the reward pool.
    function setWallets(address admin_, address marketing_, address leaders_, address liquidity_, address stability_) external onlyAuth {
        require(admin_ != address(0) && marketing_ != address(0) && leaders_ != address(0) && liquidity_ != address(0) && stability_ != address(0), "ZERO_WALLET");
        adminWallet = admin_;
        marketingWallet = marketing_;
        leadersWallet = leaders_;
        liquidityWallet = liquidity_;
        stabilityWallet = stability_;
        emit WalletsSet(admin_, marketing_, leaders_, liquidity_, stability_);
    }

    /// @notice Set the deposit split (admin+marketing+leaders+tokenLiquidity must sum to 100%; lp ≤ tokenLiquidity).
    function setSplit(uint256 admin_, uint256 marketing_, uint256 leaders_, uint256 tokenLiquidity_, uint256 lp_) external onlyAuth {
        adminBps = admin_;
        marketingBps = marketing_;
        leadersBps = leaders_;
        tokenLiquidityBps = tokenLiquidity_;
        lpBps = lp_;
        _requireValidSplit();
        emit SplitSet(admin_, marketing_, leaders_, tokenLiquidity_, lp_);
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
    function setTierTable(uint256[6] calldata entry, uint256[6] calldata productBps, uint256[6] calldata overrideBps, uint256[6] calldata stabilityBps) external onlyAuth {
        for (uint256 i = 0; i < 6; i++) {
            require(entry[i] > 0, "ZERO_ENTRY");
            if (i > 0) require(entry[i] > entry[i - 1], "NOT_INCREASING");
            require(productBps[i] <= BPS && overrideBps[i] <= BPS && stabilityBps[i] <= BPS, "BPS_TOO_HIGH");
        }
        tierEntry = entry;
        tierProductBps = productBps;
        tierOverrideBps = overrideBps;
        tierStabilityBps = stabilityBps;
        emit TierTableSet(entry, productBps, overrideBps, stabilityBps);
    }

    /// @notice Set the Black Diamond cycle-scaled stability fees (each ≤ 100%).
    function setBdStability(uint256[5] calldata bps) external onlyAuth {
        for (uint256 i = 0; i < 5; i++) require(bps[i] <= BPS, "BPS_TOO_HIGH");
        bdStabilityBps = bps;
        emit BdStabilitySet(bps);
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
        require(adminBps + marketingBps + leadersBps + tokenLiquidityBps == BPS, "BAD_SPLIT");
        require(lpBps <= tokenLiquidityBps, "LP_GT_LIQUIDITY");
    }

    /* -------------------------- LP routing helpers --------------------- */
    /// @dev Route `amount` USDT to the LP manager (best-effort). Sweeps the surplus out of the vault, hands
    ///      it to the manager, then returns any leftover to the reward pool. Never reverts activate.
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
