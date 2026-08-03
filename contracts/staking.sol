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
 * Staking Module — the COCT Staking Program (see STAKING.md, the source of truth).
 *
 * Long-term staking of COCT. Members lock COCT from their COCTAssets vault balance into a tier
 * (Starter / Growth / Institutional). Each tier accrues a fixed DAILY reward (in COCT) throughout
 * its lock period; after the lock, principal is released on a 2.5%/month vesting schedule. Every
 * new stake also pays a referral + unilevel override up the COCTAccounts referral tree — 5% to the
 * direct sponsor and 1% to each of levels 2–6 (10% total) — paid in USDT.
 */

/* -------------------------------------------------------------------------- */
/*                          Dependency interfaces                             */
/* -------------------------------------------------------------------------- */
/// @title ICOCTAccounts
/// @notice COCTAccounts — the referral tree + membership/authority registry (single source of truth).
interface ICOCTAccounts {
    function isUser(address account) external view returns (bool);
    function checkIsAdmin(address account) external view returns (bool);
    function getAffiliate(address user) external view returns (address referral, uint256 directCount);
}

/// @title ICOCTAssets
/// @notice COCTAssets — the token custody vault. Staking debits/credits internal balances here; it is
///         authorized because it is registered as an admin in COCTAccounts (assets.onlyAuth passes via
///         accounts.checkIsAdmin). No raw ERC-20 transfers happen in this contract.
interface ICOCTAssets {
    function balanceOf(address user, address token) external view returns (uint256);
    function creditBalance(address user, address token, uint256 amount) external;
    function debitBalance(address user, address token, uint256 amount) external;
}

/* -------------------------------------------------------------------------- */
/* -------------------------------------------------------------------------- */
/*                       ReentrancyGuard (minimal, inlined)                   */
/* -------------------------------------------------------------------------- */
/// @title ReentrancyGuard
/// @notice Minimal non-reentrancy guard (1 = idle, 2 = entered) for the state-changing entry points.
abstract contract ReentrancyGuard {
    uint256 private _status = 1;

    modifier nonReentrant() {
        require(_status == 1, "REENTRANCY");
        _status = 2;
        _;
        _status = 1;
    }
}

/* ========================================================================== */
/*                                COCTStaking                                 */
/* ========================================================================== */
/// @title COCTStaking
/// @author COCT
/// @notice Tiered, lock-based COCT staking funded from the COCTAssets vault, with per-tier daily
///         reward accrual, post-lock 2.5%/month principal vesting, and a 10% USDT referral/unilevel
///         override paid up the COCTAccounts referral tree on every stake.
/// @dev Deploy AFTER accounts + assets, then `accounts.addAdmin(<this>)` so it can move vault balances
///      (assets.onlyAuth == accounts.checkIsAdmin). Staking rewards (COCT) and referral
///      payouts (USDT) are credited as vault balances — the project must keep the vault funded with
///      enough COCT (reward pool) and USDT (referral pool) to back withdrawals.
contract COCTStaking is ReentrancyGuard {
    uint256 private constant BPS = 10_000;
    uint256 private constant ONE_DAY = 1 days;
    uint256 private constant ONE_MONTH = 30 days;

    /// @notice COCT — the staked token + staking-reward token (BSC, 18 decimals).
    address public constant COCT = 0x13c6f832A8eA9D450FBc04c73b59D2A66ae12A77;
    /// @notice USDT — the token the referral/unilevel override is paid in (BSC, 18 decimals).
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    /* ------------------------------- Wiring ---------------------------- */
    /// @notice COCTAccounts registry — referral tree + admin/membership authority (the SST).
    ICOCTAccounts public accounts;
    /// @notice COCTAssets vault — internal COCT/USDT balances this contract debits and credits.
    ICOCTAssets public assets;

    /* ------------------------------- Tiers ----------------------------- */
    /// @param dailyBps    Daily reward, in bps of principal (Starter 33 = 0.33%, ~10%/mo).
    /// @param lockDuration Lock length in seconds.
    /// @param enabled     Whether new stakes into this tier are accepted.
    struct Tier {
        uint256 dailyBps;
        uint256 lockDuration;
        bool enabled;
    }
    /// @notice Configured staking tiers by id (0 = Starter, 1 = Growth, 2 = Institutional).
    Tier[] public tiers;

    /* ----------------------------- Positions --------------------------- */
    /// @param tierId            The tier this position was staked into.
    /// @param principal         COCT principal locked.
    /// @param startTime         Unix timestamp the position was opened.
    /// @param lockEnd           Unix timestamp the lock ends.
    /// @param lastClaim         Reward-accrual watermark (last time rewards were claimed).
    /// @param principalReleased COCT principal already returned via post-lock vesting.
    /// @param active            False once the position is fully released/closed.
    struct Position {
        uint256 tierId;
        uint256 principal;
        uint256 startTime;
        uint256 lockEnd;
        uint256 lastClaim;
        uint256 principalReleased;
        bool active;
    }
    /// @notice Per-user array of stake positions, indexed in creation order.
    mapping(address => Position[]) public positions;

    /* --------------------- Referral / unilevel plan -------------------- */
    /// @notice Direct (level-1) referral rate — default 5%.
    uint256 public directBps = 500;
    /// @notice Indirect override rate per level — default 1% each.
    uint256 public indirectBps = 100;
    /// @notice Number of indirect levels paid, starting at level 2 — default 5 (levels 2..6).
    uint256 public indirectLevels = 5;

    /* ------------------------------ Vesting ---------------------------- */
    /// @notice Principal released per month after the lock ends — default 2.5% (250 bps). See STAKING.md.
    uint256 public vestingBps = 250;

    /* ------------------------------ Totals ----------------------------- */
    /// @notice Total COCT principal currently locked (net of principal already released).
    uint256 public totalStaked;
    /// @notice Cumulative COCT staking rewards credited to members.
    uint256 public totalRewardsClaimed;
    /// @notice Cumulative USDT referral/unilevel override credited to uplines.
    uint256 public totalReferralPaid;

    /* ------------------------------- Pause ----------------------------- */
    /// @notice When true, stake / claimRewards / claimPrincipal are blocked (views still work).
    bool public paused;

    /* ------------------------------- Events ---------------------------- */
    /// @notice Emitted when a member locks COCT into a tier.
    /// @param user The staker.
    /// @param index The new position's index in the staker's positions array.
    /// @param tierId The tier staked into.
    /// @param amount COCT principal locked.
    /// @param lockEnd Unix timestamp when the lock ends.
    event Staked(address indexed user, uint256 indexed index, uint256 tierId, uint256 amount, uint256 lockEnd);
    /// @notice Emitted when accrued COCT staking rewards are claimed for a position.
    /// @param user The staker.
    /// @param index Position index.
    /// @param amount COCT rewards credited to the vault.
    event RewardClaimed(address indexed user, uint256 indexed index, uint256 amount);
    /// @notice Emitted when a vested slice of principal is released after the lock.
    /// @param user The staker.
    /// @param index Position index.
    /// @param amount COCT principal credited to the vault.
    event PrincipalReleased(address indexed user, uint256 indexed index, uint256 amount);
    /// @notice Emitted when a USDT referral/unilevel override is paid to an upline.
    /// @param earner The upline credited.
    /// @param source The staker whose stake generated the override.
    /// @param level Referral depth (1 = direct sponsor).
    /// @param amount USDT credited.
    event ReferralPaid(address indexed earner, address indexed source, uint256 level, uint256 amount);
    /// @notice Emitted when a tier is added or updated.
    /// @param tierId The tier id.
    /// @param dailyBps Daily reward in bps of principal.
    /// @param lockDuration Lock length in seconds.
    /// @param enabled Whether new stakes into the tier are accepted.
    event TierSet(uint256 indexed tierId, uint256 dailyBps, uint256 lockDuration, bool enabled);
    /// @notice Emitted when the referral/unilevel override plan is reconfigured.
    /// @param directBps Level-1 (direct) rate in bps.
    /// @param indirectBps Per-level indirect rate in bps.
    /// @param indirectLevels Number of indirect levels paid (starting at level 2).
    event ReferralPlanSet(uint256 directBps, uint256 indirectBps, uint256 indirectLevels);
    /// @notice Emitted when the monthly principal-vesting rate changes.
    /// @param vestingBps Principal released per month, in bps.
    event VestingSet(uint256 vestingBps);
    /// @notice Emitted when the accounts/assets wiring is re-pointed.
    /// @param accounts New COCTAccounts address.
    /// @param assets New COCTAssets address.
    event ContractsSet(address accounts, address assets);
    /// @notice Emitted when the pause flag is toggled.
    /// @param paused New pause state.
    event PausedSet(bool paused);

    /* ------------------------------ Modifiers -------------------------- */
    /// @dev Admin authority sourced from COCTAccounts (its owner or an explicit admin) — the SST.
    modifier onlyAuth() {
        require(accounts.checkIsAdmin(msg.sender), "NOT_AUTH");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "PAUSED");
        _;
    }

    /* ----------------------------- Constructor ------------------------- */
    /// @notice Wire to accounts + assets and seed the three tiers from STAKING.md.
    /// @param accountsAddr COCTAccounts registry address (non-zero).
    /// @param assetsAddr COCTAssets vault address (non-zero).
    constructor(address accountsAddr, address assetsAddr) {
        require(accountsAddr != address(0) && assetsAddr != address(0), "ZERO_DEP");
        accounts = ICOCTAccounts(accountsAddr);
        assets = ICOCTAssets(assetsAddr);

        // Starter: 0.33%/day (~10%/mo), 12-month lock
        tiers.push(Tier({dailyBps: 33, lockDuration: 12 * ONE_MONTH, enabled: true}));
        // Growth: 0.40%/day (~12%/mo), 10-month lock
        tiers.push(Tier({dailyBps: 40, lockDuration: 10 * ONE_MONTH, enabled: true}));
        // Institutional: 0.50%/day (~15%/mo), 8-month lock
        tiers.push(Tier({dailyBps: 50, lockDuration: 8 * ONE_MONTH, enabled: true}));
    }

    /* =============================== STAKE ============================= */
    /// @notice Lock `amount` COCT from your COCTAssets vault balance into `tierId`. Requires you to be
    ///         registered (COCTAccounts) and to hold at least `amount` COCT in the vault. Pays the
    ///         referral/unilevel override to your uplines in USDT.
    /// @param tierId 0 = Starter, 1 = Growth, 2 = Institutional.
    /// @param amount COCT to stake (18 decimals).
    function stake(uint256 tierId, uint256 amount) external nonReentrant whenNotPaused {
        require(tierId < tiers.length && tiers[tierId].enabled, "BAD_TIER");
        require(amount > 0, "ZERO_AMOUNT");
        address user = msg.sender;
        require(accounts.isUser(user), "NOT_REGISTERED");
        require(assets.balanceOf(user, COCT) >= amount, "INSUFFICIENT_BALANCE");

        // Lock the principal — debit COCT from the member's vault balance.
        assets.debitBalance(user, COCT, amount);

        uint256 lockEnd = block.timestamp + tiers[tierId].lockDuration;
        positions[user].push(
            Position({
                tierId: tierId,
                principal: amount,
                startTime: block.timestamp,
                lockEnd: lockEnd,
                lastClaim: block.timestamp,
                principalReleased: 0,
                active: true
            })
        );
        totalStaked += amount;

        // Pay the referral + unilevel override up the chain, in USDT.
        _distributeReferral(user, amount);

        emit Staked(user, positions[user].length - 1, tierId, amount, lockEnd);
    }

    /* ============================ REWARDS ============================= */
    /// @notice Claim accrued COCT staking rewards for one position into your vault balance.
    /// @param index Position index (see positionsCount).
    function claimRewards(uint256 index) external nonReentrant whenNotPaused {
        Position storage p = positions[msg.sender][index];
        require(p.active, "INACTIVE");
        uint256 amount = _accrued(p);
        require(amount > 0, "NOTHING_TO_CLAIM");

        // Watermark advances to now, capped at lock end (rewards accrue only during the lock period).
        p.lastClaim = block.timestamp < p.lockEnd ? block.timestamp : p.lockEnd;

        totalRewardsClaimed += amount;
        assets.creditBalance(msg.sender, COCT, amount);
        emit RewardClaimed(msg.sender, index, amount);
    }

    /// @dev Rewards = principal × dailyBps/BPS per day, prorated by seconds, accruing only up to lockEnd.
    function _accrued(Position storage p) internal view returns (uint256) {
        if (!p.active) return 0;
        uint256 upTo = block.timestamp < p.lockEnd ? block.timestamp : p.lockEnd;
        if (upTo <= p.lastClaim) return 0;
        uint256 elapsed = upTo - p.lastClaim;
        return (p.principal * tiers[p.tierId].dailyBps * elapsed) / (BPS * ONE_DAY);
    }

    /* ========================= PRINCIPAL VESTING ====================== */
    /// @notice After the lock ends, release the newly-vested slice of principal (2.5%/month) into your
    ///         vault balance. Call once per month (or later — vesting accumulates).
    /// @param index Position index.
    function claimPrincipal(uint256 index) external nonReentrant whenNotPaused {
        Position storage p = positions[msg.sender][index];
        require(p.active, "INACTIVE");
        require(block.timestamp >= p.lockEnd, "LOCKED");

        uint256 vested = _vestedPrincipal(p);
        uint256 releasable = vested - p.principalReleased;
        require(releasable > 0, "NOTHING_VESTED");

        p.principalReleased += releasable;
        if (p.principalReleased >= p.principal) p.active = false;

        totalStaked -= releasable;
        assets.creditBalance(msg.sender, COCT, releasable);
        emit PrincipalReleased(msg.sender, index, releasable);
    }

    /// @dev Cumulative principal vested by now: principal × vestingBps/BPS × whole months since lockEnd,
    ///      capped at the full principal. (At 2.5%/mo, full release takes 40 months.)
    function _vestedPrincipal(Position storage p) internal view returns (uint256) {
        if (block.timestamp < p.lockEnd) return 0;
        uint256 monthsElapsed = (block.timestamp - p.lockEnd) / ONE_MONTH;
        uint256 vested = (p.principal * vestingBps * monthsElapsed) / BPS;
        return vested > p.principal ? p.principal : vested;
    }

    /* ===================== Referral / unilevel plan =================== */
    /// @dev Walk up the referral tree paying the override in USDT: level 1 = directBps (5%), levels
    ///      2..(1+indirectLevels) = indirectBps (1%) each. A missing upline (the tree is shallower than
    ///      the plan) simply ends the walk. Payouts are credited as USDT vault balances (project-funded
    ///      referral pool).
    function _distributeReferral(address staker, uint256 base) internal {
        uint256 maxLevel = 1 + indirectLevels;
        address up = staker;
        for (uint256 level = 1; level <= maxLevel; level++) {
            (up, ) = accounts.getAffiliate(up);
            if (up == address(0)) break; // reached the tree root — no higher uplines

            uint256 bps = level == 1 ? directBps : indirectBps;
            if (bps == 0) continue;
            uint256 reward = (base * bps) / BPS;
            if (reward == 0) continue;

            assets.creditBalance(up, USDT, reward);
            totalReferralPaid += reward;
            emit ReferralPaid(up, staker, level, reward);
        }
    }

    /* ============================== VIEWS ============================= */
    /// @notice Number of stake positions a user holds (including fully-released/closed ones).
    /// @param user The account to query.
    /// @return The number of stake positions held by `user`.
    function positionsCount(address user) external view returns (uint256) {
        return positions[user].length;
    }

    /// @notice Full position record.
    /// @param user The account to query.
    /// @param index Position index.
    /// @return The full Position struct at that index.
    function getPosition(address user, uint256 index) external view returns (Position memory) {
        return positions[user][index];
    }

    /// @notice Unclaimed COCT staking rewards accrued on a position right now.
    /// @param user The account to query.
    /// @param index Position index.
    /// @return Unclaimed COCT rewards accrued on the position.
    function pendingRewards(address user, uint256 index) external view returns (uint256) {
        return _accrued(positions[user][index]);
    }

    /// @notice COCT principal currently releasable (vested but not yet claimed) on a position.
    /// @param user The account to query.
    /// @param index Position index.
    /// @return COCT principal vested but not yet claimed (0 if the position is inactive).
    function releasablePrincipal(address user, uint256 index) external view returns (uint256) {
        Position storage p = positions[user][index];
        if (!p.active) return 0;
        return _vestedPrincipal(p) - p.principalReleased;
    }

    /// @notice Number of configured tiers.
    /// @return The number of configured tiers.
    function tierCount() external view returns (uint256) {
        return tiers.length;
    }

    /// @notice The USDT override paid per level for a given stake base: [L1, L2, …, L(1+indirectLevels)].
    /// @param base The stake base to compute the override against.
    /// @return perLevel USDT override per level, indexed [L1 .. L(1+indirectLevels)].
    function referralBreakdown(uint256 base) external view returns (uint256[] memory perLevel) {
        uint256 maxLevel = 1 + indirectLevels;
        perLevel = new uint256[](maxLevel);
        for (uint256 level = 1; level <= maxLevel; level++) {
            uint256 bps = level == 1 ? directBps : indirectBps;
            perLevel[level - 1] = (base * bps) / BPS;
        }
    }

    /* ============================== ADMIN ============================= */
    /// @notice Add or update a tier. `tierId == tiers.length` appends a new tier.
    /// @param tierId Tier id to update; passing `tiers.length` appends a new tier.
    /// @param dailyBps Daily reward in bps of principal (<= BPS).
    /// @param lockDuration Lock length in seconds (> 0).
    /// @param enabled Whether new stakes into the tier are accepted.
    function setTier(uint256 tierId, uint256 dailyBps, uint256 lockDuration, bool enabled) external onlyAuth {
        require(dailyBps <= BPS, "BAD_DAILY_BPS");
        require(lockDuration > 0, "BAD_LOCK");
        if (tierId == tiers.length) {
            tiers.push(Tier({dailyBps: dailyBps, lockDuration: lockDuration, enabled: enabled}));
        } else {
            require(tierId < tiers.length, "BAD_TIER");
            tiers[tierId] = Tier({dailyBps: dailyBps, lockDuration: lockDuration, enabled: enabled});
        }
        emit TierSet(tierId, dailyBps, lockDuration, enabled);
    }

    /// @notice Configure the referral/unilevel override plan.
    /// @param direct Level-1 (direct) rate in bps.
    /// @param indirect Per-level indirect rate in bps.
    /// @param levels Number of indirect levels (<= 50); direct + indirect*levels must be <= BPS.
    function setReferralPlan(
        uint256 direct,
        uint256 indirect,
        uint256 levels
    ) external onlyAuth {
        require(levels <= 50, "TOO_MANY_LEVELS");
        require(direct + indirect * levels <= BPS, "OVER_100_PCT");
        directBps = direct;
        indirectBps = indirect;
        indirectLevels = levels;
        emit ReferralPlanSet(direct, indirect, levels);
    }

    /// @notice Set the monthly principal-vesting rate (bps). Default 250 (2.5%).
    /// @param bps Monthly principal-vesting rate in bps (0 < bps <= BPS).
    function setVesting(uint256 bps) external onlyAuth {
        require(bps > 0 && bps <= BPS, "BAD_VESTING");
        vestingBps = bps;
        emit VestingSet(bps);
    }

    /// @notice Re-point the accounts / assets contracts. Owner-only, trust-critical wiring.
    /// @param accountsAddr New COCTAccounts address (non-zero).
    /// @param assetsAddr New COCTAssets address (non-zero).
    function setContracts(address accountsAddr, address assetsAddr) external onlyAuth {
        require(accountsAddr != address(0) && assetsAddr != address(0), "ZERO_DEP");
        accounts = ICOCTAccounts(accountsAddr);
        assets = ICOCTAssets(assetsAddr);
        emit ContractsSet(accountsAddr, assetsAddr);
    }

    /// @notice Pause or unpause stake / claim / release.
    /// @param _paused New pause state (true = paused).
    function setPaused(bool _paused) external onlyAuth {
        paused = _paused;
        emit PausedSet(_paused);
    }
}
