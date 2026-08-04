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
 * Assets Module — multi-token custody vault
 * Holds every user's BEP20 balances. The COCT accounts is the single source of truth for
 * membership: an account must be a registered user (isUser) to deposit or withdraw.
 */

/* -------------------------------------------------------------------------- */
/*                        IERC20 (minimal BEP20 interface)                    */
/* -------------------------------------------------------------------------- */
/// @title IERC20
/// @notice The subset of the BEP20 / ERC20 interface this vault uses to move token assets.
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/* -------------------------------------------------------------------------- */
/*                  ICOCTAccounts (single source of truth)                  */
/* -------------------------------------------------------------------------- */
/// @title ICOCTAccounts
/// @notice The membership view this vault reads from the COCT accounts contract. `isUser` is the
///         auto-generated getter of the accounts's public `isUser` mapping.
interface ICOCTAccounts {
    /// @notice True if `account` is a registered user in the accounts.
    /// @param account The address to check.
    /// @return True if the address is a registered user.
    function isUser(address account) external view returns (bool);
    /// @notice True if `account` has admin authority in the accounts — i.e. it is the accounts owner
    ///         OR an explicit admin. Read here so the accounts is the single source of truth for who
    ///         may act as a mod.
    /// @param account The address to check for admin authority.
    /// @return True if the address is the accounts owner or an explicit admin.
    function checkIsAdmin(address account) external view returns (bool);
    /// @notice The accounts contract owner — the single highest authority (used to gate the emergency
    ///         `rescueToken` lever, which is tighter than the admin-level `onlyAuth`).
    /// @return The current owner address.
    function owner() external view returns (address);
}

/* -------------------------------------------------------------------------- */
/*                       ReentrancyGuard (minimal, inlined)                   */
/* -------------------------------------------------------------------------- */
/// @title ReentrancyGuard
/// @author COCT
/// @notice Prevents nested (re-entrant) calls to functions marked `nonReentrant`.
abstract contract ReentrancyGuard {
    uint256 private _status = 1; // 1 = not entered, 2 = entered

    modifier nonReentrant() {
        require(_status == 1, "REENTRANCY");
        _status = 2;
        _;
        _status = 1;
    }
}

/* ========================================================================== */
/*                                COCTAssets                                  */
/* ========================================================================== */
/// @title COCTAssets
/// @author COCT
/// @notice Multi-token custody vault for COCT. Tracks each user's per-token balance held in the
///         contract. Membership is enforced against the COCT accounts (the single source of truth):
///         deposit and withdraw both require `isUser`.
/// @dev Self-contained (inlined ReentrancyGuard). Uses IERC20 for BEP20 transfers via safe wrappers that
///      tolerate non-returning tokens. `onlyAuth` (any accounts admin — the owner or a registered admin
///      such as the membership/staking hubs) can move internal balances between users for payouts.
contract COCTAssets is ReentrancyGuard {
    /* ------------------------------- Wiring ---------------------------- */
    /// @notice The COCT accounts contract — the single source of truth for isUser and authorization.
    ///         Immutable: fixed at deployment and can never be repointed, so no admin can capture the vault
    ///         by swapping in a malicious accounts, brick it, or persist authority after being removed.
    ICOCTAccounts public immutable accounts;
    /// @notice When true, deposit and withdraw are blocked.
    bool public paused;

    /* ------------------------------ Balances --------------------------- */
    /// @notice Vault balance per user, per token: balances[user][token].
    mapping(address => mapping(address => uint256)) public balances;
    /// @notice Per-token sum of all attributed internal balances (the vault's liabilities). Kept in sync
    ///         with every `balances` mutation. Solvency invariant: totalTracked[token] <= real holdings,
    ///         so no ledger balance can ever be created that the vault does not physically back.
    mapping(address => uint256) public totalTracked;

    /* ------------------------- Withdrawal limits ----------------------- */
    /// @notice Basis-points denominator (10000 = 100%) for the withdrawal fee.
    uint256 public constant BPS_DENOMINATOR = 10_000;
    /// @notice Per-account withdrawal gate: block.timestamp must be GREATER than coolDown[account] before
    ///         that account can withdraw again. Refreshed on every withdrawal that sends tokens out.
    mapping(address => uint256) public coolDown;
    /// @notice Seconds an account must wait between withdrawals. 0 disables the cooldown.
    uint256 public withdrawal_cooldown = 24 hours;
    /// @notice Withdrawal fee in basis points, retained in the vault as surplus. Default 0 — the compensation
    ///         plan's stability fee is applied in rewards.sol (on withdrawRewards), so the vault takes no fee
    ///         by default. Kept as an optional lever; set with `setWithdrawalFee`.
    uint256 public withdrawal_fee = 0;
    /// @notice Allowed withdrawal denominations (gross amounts) — the sole amount gate. A withdrawal's
    ///         `amount` must equal one of these. Defaults to {20, 50, 100} USDT (18-dp). An EMPTY set
    ///         disables the check (any amount up to the balance). Set with `setWithdrawalDenominations`.
    uint256[] public withdrawalDenominations;

    /* ------------------------------- Events ---------------------------- */
    /// @notice Emitted when `user` deposits `amount` of `token` into their vault balance.
    /// @param user The depositor.
    /// @param token The BEP20 token deposited.
    /// @param amount The actual amount credited (measured balance delta).
    event Deposited(address indexed user, address indexed token, uint256 amount);
    /// @notice Emitted when `user` withdraws `amount` of `token` from their vault balance.
    /// @param user The withdrawer.
    /// @param token The BEP20 token withdrawn.
    /// @param amount The gross amount debited from the balance (the net sent is `amount` minus the fee).
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    /// @notice Emitted when the mod moves internal balance from `from` to `to` (compensation payout).
    /// @param from The account debited.
    /// @param to The account credited.
    /// @param token The token whose internal balance moved.
    /// @param amount The amount moved.
    event BalanceTransfer(address indexed from, address indexed to, address indexed token, uint256 amount);
    /// @notice Emitted when the mod credits a user's balance (e.g. a reward claim).
    /// @param user The member credited.
    /// @param token The token credited.
    /// @param amount The amount added.
    event BalanceCredited(address indexed user, address indexed token, uint256 amount);
    /// @notice Emitted when the mod debits a user's balance (e.g. a membership/subscription charge).
    /// @param user The member debited.
    /// @param token The token debited.
    /// @param amount The amount removed.
    event BalanceDebited(address indexed user, address indexed token, uint256 amount);
    /// @notice Emitted when an admin withdraws `amount` of `token` from `to`'s balance to `to`'s wallet.
    /// @param token The BEP20 token sent out.
    /// @param to The member whose balance was debited and who received the tokens.
    /// @param amount The gross amount debited from `to` (the net sent is `amount` minus the fee).
    event BalanceWithdrawn(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when an admin sweeps unattributed surplus out of the vault (e.g. to fund the LP).
    /// @param token The BEP20 token swept.
    /// @param to The recipient of the surplus.
    /// @param amount The amount of surplus sent out.
    event SurplusSwept(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when the owner rescues (drains) the vault's full balance of a token.
    /// @param token The BEP20 token rescued.
    /// @param to The recipient (the accounts owner).
    /// @param amount The full balance transferred out.
    event TokenRescued(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted once at deployment when the immutable accounts (source of truth) is set.
    /// @param accounts The accounts contract address wired in at construction.
    event AccountsSet(address indexed accounts);
    /// @notice Emitted when the pause flag is set.
    /// @param paused The new pause state.
    event PausedSet(bool paused);
    /// @notice Emitted when the per-account withdrawal cooldown (seconds) is changed.
    /// @param cooldown The new cooldown in seconds (0 = disabled).
    event WithdrawalCooldownSet(uint256 cooldown);
    /// @notice Emitted when the withdrawal fee (basis points) is changed.
    /// @param feeBps The new fee in basis points (0 = disabled).
    event WithdrawalFeeSet(uint256 feeBps);
    /// @notice Emitted when the allowed withdrawal denomination set is changed.
    /// @param denominations The new set of allowed gross withdrawal amounts (empty = no restriction).
    event WithdrawalDenominationsSet(uint256[] denominations);

    /* ------------------------------ Modifiers -------------------------- */
    /// @dev Restricts a function to anyone with admin authority in the accounts (its owner or an explicit
    ///      admin) — the accounts is the single source of truth for authorization. The membership + staking
    ///      hubs are registered via accounts.addAdmin, so they pass here. Reverts NOT_AUTH.
    modifier onlyAuth() {
        require(accounts.checkIsAdmin(msg.sender), "NOT_AUTH");
        _;
    }

    /// @dev Blocks the guarded function while the vault is paused; reverts PAUSED.
    modifier whenNotPaused() {
        require(!paused, "PAUSED");
        _;
    }

    /* ----------------------------- Constructor ------------------------- */
    /// @notice Deploy the vault wired to the COCT accounts (deploy the accounts first). `accounts` is
    ///         immutable — fixed here and never repointable — so pass the real accounts for the target
    ///         network. The vault holds no LP wiring; the compensation plan's stability fee + LP routing
    ///         live entirely in rewards.sol.
    /// @param accountsAddr The deployed COCT accounts contract (non-zero, must be a contract).
    /// @dev Reverts ZERO_ACCOUNTS / NOT_CONTRACT.
    constructor(address accountsAddr) {
        require(accountsAddr != address(0), "ZERO_ACCOUNTS");
        require(accountsAddr.code.length > 0, "NOT_CONTRACT");
        accounts = ICOCTAccounts(accountsAddr);
        // Default withdrawal denominations: $20 / $50 / $100 (USDT, 18-dp).
        withdrawalDenominations.push(20 ether);
        withdrawalDenominations.push(50 ether);
        withdrawalDenominations.push(100 ether);
        emit AccountsSet(accountsAddr);
        emit WithdrawalDenominationsSet(withdrawalDenominations);
    }

    /* ============================ USER — DEPOSIT ======================== */
    /// @notice Deposit `amount` of `tokenAddress` into your vault balance. Requires the caller to be a
    ///         registered member in the accounts. Approve this contract on the token first.
    /// @param tokenAddress The BEP20 token to deposit.
    /// @param amount The amount to pull from the caller (18-dp for USDT on BSC).
    /// @dev Credits the ACTUAL amount received (balance delta), so fee-on-transfer tokens can't
    ///      over-credit. nonReentrant + whenNotPaused.
    function deposit(address tokenAddress, uint256 amount) external nonReentrant whenNotPaused {
        require(accounts.isUser(msg.sender), "NOT_REGISTERED");
        require(amount > 0, "ZERO_AMOUNT");

        uint256 balBefore = IERC20(tokenAddress).balanceOf(address(this));
        _safeTransferFrom(tokenAddress, msg.sender, address(this), amount);
        uint256 received = IERC20(tokenAddress).balanceOf(address(this)) - balBefore;
        require(received > 0, "NOTHING_RECEIVED");

        balances[msg.sender][tokenAddress] += received;
        totalTracked[tokenAddress] += received;
        emit Deposited(msg.sender, tokenAddress, received);
    }

    /* ============================ USER — WITHDRAW ======================= */
    /// @notice Withdraw `amount` of `tokenAddress` from your vault balance. Requires the caller to be
    ///         a registered user in the accounts.
    /// @param tokenAddress The BEP20 token to withdraw.
    /// @param amount The gross amount to debit; you receive `amount` minus the withdrawal fee.
    /// @dev nonReentrant + whenNotPaused. Enforces the allowed denominations, the per-account cooldown, and
    ///      the bps fee via `_withdrawTo` (CEI: balance debited before the external transfer).
    function withdraw(address tokenAddress, uint256 amount) external nonReentrant whenNotPaused {
        require(accounts.isUser(msg.sender), "NOT_REGISTERED");
        require(amount > 0, "ZERO_AMOUNT");
        _withdrawTo(msg.sender, tokenAddress, amount);
        emit Withdrawn(msg.sender, tokenAddress, amount);
    }

    /// @notice Credit `amount` of `tokenAddress` to `user`'s vault balance — e.g. paying out a reward
    ///         the user claimed through the membership hub.
    /// @param user The member to credit.
    /// @param tokenAddress The token to credit.
    /// @param amount The amount to add.
    /// @dev onlyAuth, nonReentrant, whenNotPaused. Increases a balance with NO token inflow, so the reward
    ///      pool must be pre-funded: reverts UNBACKED unless the vault physically holds enough surplus to
    ///      back the new credit (totalTracked[token] + amount <= real holdings). This enforces the solvency
    ///      invariant — the credited-and-withdrawn "mint from nothing" drain can no longer exceed holdings.
    function creditBalance(
        address user,
        address tokenAddress,
        uint256 amount
    ) external onlyAuth nonReentrant whenNotPaused {
        require(user != address(0), "ZERO_USER");
        require(amount > 0, "ZERO_AMOUNT");
        require(
            totalTracked[tokenAddress] + amount <= IERC20(tokenAddress).balanceOf(address(this)),
            "UNBACKED"
        );
        totalTracked[tokenAddress] += amount;
        balances[user][tokenAddress] += amount;
        emit BalanceCredited(user, tokenAddress, amount);
    }

    /// @notice Deduct `amount` of `tokenAddress` from `user`'s vault balance — e.g. charging a
    ///         membership / subscription fee through the membership hub.
    /// @param user The member to debit.
    /// @param tokenAddress The token to debit.
    /// @param amount The amount to remove.
    /// @dev onlyAuth. The deducted tokens STAY in the vault (now unattributed) — they become pool /
    ///      company funds. Reverts INSUFFICIENT_BALANCE if the member's balance is too low.
    function debitBalance(address user, address tokenAddress, uint256 amount) external onlyAuth whenNotPaused {
        require(amount > 0, "ZERO_AMOUNT");
        uint256 bal = balances[user][tokenAddress];
        require(bal >= amount, "INSUFFICIENT_BALANCE");
        balances[user][tokenAddress] = bal - amount;
        totalTracked[tokenAddress] -= amount;
        emit BalanceDebited(user, tokenAddress, amount);
    }

    /* ============================ MOD — PAYOUTS ========================= */
    /// @notice Move internal vault balance from `from` to `to` — the primitive the membership hub uses to
    ///         credit compensation/bonuses from a pool account to members. No tokens leave the vault.
    /// @param from The account to debit (e.g. a company/pool account).
    /// @param to The account to credit.
    /// @param tokenAddress The token whose internal balance moves.
    /// @param amount The amount to move.
    /// @dev onlyAuth. Pure bookkeeping — recipients withdraw via `withdraw` once registered.
    function balanceTransfer(
        address from,
        address to,
        address tokenAddress,
        uint256 amount
    ) external onlyAuth whenNotPaused {
        require(to != address(0), "ZERO_TO");
        require(amount > 0, "ZERO_AMOUNT");
        uint256 bal = balances[from][tokenAddress];
        require(bal >= amount, "INSUFFICIENT_BALANCE");

        balances[from][tokenAddress] = bal - amount;
        balances[to][tokenAddress] += amount;
        emit BalanceTransfer(from, to, tokenAddress, amount);
    }


    /// @notice Withdraw `amount` of `tokenAddress` from `to`'s vault balance and send the real tokens to `to`.
    ///         Admin-initiated payout of a member's OWN attributed balance (assisted / automated withdrawal).
    /// @param tokenAddress The BEP20 token to send out.
    /// @param to The member whose balance is debited AND the recipient of the tokens.
    /// @param amount The gross amount to debit from `to`; `to` receives `amount` minus the withdrawal fee.
    /// @dev onlyAuth, nonReentrant. Subject to the SAME allowed denominations, per-account cooldown (keyed by
    ///      `to`), and bps fee as user `withdraw`, via `_withdrawTo` (CEI). Reverts ZERO_TO / ZERO_AMOUNT /
    ///      INSUFFICIENT_BALANCE / BAD_DENOMINATION / COOLDOWN / NET_ZERO. Solvency-preserving: ledger
    ///      and real holdings both drop by `amount`, so it can never move tokens backing another user.
    function balanceWithdraw(address tokenAddress, address to, uint256 amount) external onlyAuth nonReentrant whenNotPaused {
        require(to != address(0), "ZERO_TO");
        require(amount > 0, "ZERO_AMOUNT");
        _withdrawTo(to, tokenAddress, amount);
        emit BalanceWithdrawn(tokenAddress, to, amount);
    }

    /// @notice Move UNATTRIBUTED surplus (`holdings - totalTracked`) out of the vault to `to`. Used to fund
    ///         external operations — e.g. the membership hub seeding the PancakeSwap LP from the Liquidity
    ///         allocation. Not subject to the per-user withdrawal fee/denomination/cooldown.
    /// @param tokenAddress The BEP20 token to send out.
    /// @param to The recipient (e.g. the membership hub, which forwards it to the LP manager).
    /// @param amount The amount to send — must not exceed the current surplus.
    /// @dev onlyAuth, nonReentrant, whenNotPaused. Bounded by `EXCEEDS_SURPLUS`: it can ONLY move funds the
    ///      vault holds beyond its tracked liabilities, so it can never touch tokens backing a user's
    ///      balance and never breaks the solvency invariant (totalTracked is untouched; holdings drop by
    ///      `amount`, which was surplus). Replaces the old unbounded modWithdraw drain vector.
    function sweepSurplus(address tokenAddress, address to, uint256 amount) external onlyAuth nonReentrant whenNotPaused {
        require(to != address(0), "ZERO_TO");
        require(amount > 0, "ZERO_AMOUNT");
        require(
            IERC20(tokenAddress).balanceOf(address(this)) - totalTracked[tokenAddress] >= amount,
            "EXCEEDS_SURPLUS"
        );
        _safeTransfer(tokenAddress, to, amount);
        emit SurplusSwept(tokenAddress, to, amount);
    }

    /// @notice EMERGENCY: transfer this vault's ENTIRE balance of `token` to the accounts owner. Owner-only.
    /// @param token The BEP20 token to rescue.
    /// @dev ⚠️ FULL DRAIN — unlike `sweepSurplus`, this moves the whole balance, INCLUDING funds that back
    ///      user vault balances (`totalTracked`), not just surplus. `totalTracked` is left unchanged, so
    ///      after a rescue the ledger shows liabilities the vault no longer physically holds and users cannot
    ///      withdraw until the vault is refunded. It is a centralized recovery/migration lever — for routine
    ///      recovery of only the unattributed excess, use `sweepSurplus` instead. Restricted to the accounts
    ///      OWNER (tighter than the admin-level `onlyAuth`); nonReentrant. Reverts NOT_OWNER / NOTHING.
    function rescueToken(address token) external nonReentrant {
        require(msg.sender == accounts.owner(), "NOT_OWNER");
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, "NOTHING");
        _safeTransfer(token, msg.sender, bal);
        emit TokenRescued(token, msg.sender, bal);
    }

    /* ============================== ADMIN ============================== */
    /// @notice Pause or unpause deposits and withdrawals. Auth-gated (any accounts admin).
    /// @param _paused True to pause deposits/withdrawals, false to resume.
    function setPaused(bool _paused) external onlyAuth {
        paused = _paused;
        emit PausedSet(_paused);
    }

    /// @notice Set the per-account withdrawal cooldown in seconds (0 disables). Auth-gated.
    /// @param secondsBetween The new cooldown in seconds.
    function setWithdrawalCooldown(uint256 secondsBetween) external onlyAuth {
        withdrawal_cooldown = secondsBetween;
        emit WithdrawalCooldownSet(secondsBetween);
    }

    /// @notice Set the withdrawal fee in basis points (0 disables; capped at 100%). Auth-gated.
    /// @param feeBps The new fee in basis points (e.g. 500 = 5%).
    function setWithdrawalFee(uint256 feeBps) external onlyAuth {
        require(feeBps <= BPS_DENOMINATOR, "FEE_TOO_HIGH");
        withdrawal_fee = feeBps;
        emit WithdrawalFeeSet(feeBps);
    }

    /// @notice Set the allowed withdrawal denominations (gross amounts). Pass an empty array to disable the
    ///         restriction (any amount up to the balance). Auth-gated.
    /// @param denoms The new set of allowed gross withdrawal amounts (each > 0), e.g. [20e18, 50e18, 100e18].
    function setWithdrawalDenominations(uint256[] calldata denoms) external onlyAuth {
        delete withdrawalDenominations;
        for (uint256 i = 0; i < denoms.length; i++) {
            require(denoms[i] > 0, "ZERO_DENOM");
            withdrawalDenominations.push(denoms[i]);
        }
        emit WithdrawalDenominationsSet(withdrawalDenominations);
    }


    /* ============================== VIEWS ============================== */
    /// @notice A user's vault balance for a token.
    /// @param user The account to query.
    /// @param tokenAddress The token to query.
    /// @return The user's internal vault balance for that token.
    function balanceOf(address user, address tokenAddress) external view returns (uint256) {
        return balances[user][tokenAddress];
    }

    /// @notice The total amount of `tokenAddress` this vault actually holds (for reconciliation).
    /// @param tokenAddress The token to query.
    /// @return The actual token balance this vault holds.
    function vaultBalance(address tokenAddress) external view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    /// @notice The current allowed withdrawal denomination set (empty = no restriction).
    /// @return The list of allowed gross withdrawal amounts.
    function getWithdrawalDenominations() external view returns (uint256[] memory) {
        return withdrawalDenominations;
    }

    /// @notice Whether `amount` is a permitted withdrawal denomination (true for any amount when the set
    ///         is empty).
    /// @param amount The gross withdrawal amount to check.
    /// @return True if `amount` equals a configured denomination, or if no denominations are configured.
    function isAllowedDenomination(uint256 amount) public view returns (bool) {
        uint256 n = withdrawalDenominations.length;
        if (n == 0) return true; // no restriction configured
        for (uint256 i = 0; i < n; i++) {
            if (withdrawalDenominations[i] == amount) return true;
        }
        return false;
    }

    /// @notice Unattributed surplus the vault holds for a token — real holdings minus tracked liabilities
    ///         (accumulated withdrawal fees + debited/unattributed funds + direct token sends). This is the
    ///         only pool `creditBalance` can draw new credits from and the only amount an admin can move out
    ///         beyond what backs a user.
    /// @param tokenAddress The token to query.
    /// @return The surplus (0 when fully attributed).
    function surplus(address tokenAddress) external view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this)) - totalTracked[tokenAddress];
    }

    /* ------------------- Internal withdrawal pipeline ------------------ */
    /// @dev Shared withdrawal path for `withdraw` and `balanceWithdraw`. Enforces the allowed denomination
    ///      set (the sole amount gate) and the per-account cooldown (disabled when withdrawal_cooldown == 0),
    ///      debits `account`'s balance (CEI), then sends `amount` minus the bps withdrawal_fee to `account`.
    ///      The fee is retained in the vault as unattributed funds. Caller must have validated amount > 0 and
    ///      must hold the nonReentrant guard.
    /// @param account The balance holder to debit and pay out to.
    /// @param tokenAddress The token to send.
    /// @param amount The gross amount to debit from `account`'s balance.
    /// @return sent The net amount transferred out (amount minus fee).
    function _withdrawTo(address account, address tokenAddress, uint256 amount) internal returns (uint256 sent) {
        uint256 bal = balances[account][tokenAddress];
        require(bal >= amount, "INSUFFICIENT_BALANCE");

        // Allowed denominations are the amount gate (empty set disables the check).
        require(isAllowedDenomination(amount), "BAD_DENOMINATION");

        // Per-account cooldown (0 disables). block.timestamp must be past the stored gate.
        if (withdrawal_cooldown > 0) {
            require(block.timestamp > coolDown[account], "COOLDOWN");
            coolDown[account] = block.timestamp + withdrawal_cooldown;
        }

        // Effects before interaction. totalTracked drops by the gross amount (the fee stays as surplus).
        balances[account][tokenAddress] = bal - amount;
        totalTracked[tokenAddress] -= amount;

        // Withdrawal fee (bps, default 0), retained in the vault as unattributed surplus.
        uint256 fee = withdrawal_fee > 0 ? (amount * withdrawal_fee) / BPS_DENOMINATOR : 0;
        sent = amount - fee;
        require(sent > 0, "NET_ZERO");

        _safeTransfer(tokenAddress, account, sent);
    }

    /* ---------------------- Safe BEP20 transfer helpers ---------------- */
    /// @dev transfer that works with tokens returning bool AND non-returning tokens; requires the
    ///      token to be a contract so a call to an EOA can't silently "succeed".
    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0, "NOT_CONTRACT");
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    /// @dev transferFrom variant of `_safeTransfer`.
    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        require(token.code.length > 0, "NOT_CONTRACT");
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }
}
