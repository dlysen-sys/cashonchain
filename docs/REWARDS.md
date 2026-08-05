# COC Rewards — Compensation Plan (SOURCE OF TRUTH)

**Contract:** `projects/coc/contracts/rewards.sol` (`COCTRewards`) — new hub implementing this plan.
**Status:** IMPLEMENTED 2026-08-03 (rewards.sol) — awaiting tests.
**Settlement:** USDT (`0x55d398…7955`, 18-dp). **Product token:** COCT (`0x13c6f832…A77`).
**COCT initial price:** **1 COCT = 0.01 USDT** (launch/floor). Encoded as the fallback `rewards.productRate`
default = `100e18` (= `1e18 / 0.01` → 100 COCT delivered per 1 USDT of product value). Retunable on-chain via
`setProductRate` (`productRate = 1e18 / price`); the market/LP price is used directly when the swap path is live.
**Depends on:** `COCTAccounts` (referral tree + global one-line) · `COCTAssets` (solvency-guarded vault) · `COCTLiquidity` (USDT/COCT LP).

> Money-flow model: every reward is paid from the **reward pool** (the `liquidityWallet` vault balance)
> via `assets.balanceTransfer(liquidityWallet → earner)`. If the pool is dry, the claim reverts. The
> deposit split conserves each entry exactly, so the vault stays solvent by construction.

---

## 1. Ranks / Tiers
Rank **= the highest tier the member has ever activated** (never decreases).

| Rank | Entry (USDT) | Product token % | Override % | Daily-passive stability fee |
|------|--------------|-----------------|-----------|-----------------------------|
| Silver        | 20   | 0% | 0% | 5% |
| Gold          | 50   | 1% | 0% | 6% |
| Platinum      | 100  | 2% | 2% | 7% |
| Diamond       | 500  | 3% | 3% | 8% |
| Emerald       | 1000 | 4% | 4% | 9% |
| Black Diamond | 5000 | 5% | 5% | cycle-scaled (see §7) |

**Cycles:** each tier may be activated at most **5 times**, except Black Diamond ($5000) = **unlimited**.
Tracked per member per tier (`cycleCount[user][tier]`). A 6th activation of a non-BD tier reverts; the
member must pick a tier that hasn't finished its 5 cycles.

---

## 2. Entry — `activate(uint256 amount)`
- `amount` must equal a tier entry; caller must be `isUser`; the tier must have a free cycle.
- **Funded from the member's vault balance** (`deposit` USDT to `COCTAssets` first, then `activate`
  debits it). Reverts `INSUFFICIENT_FUNDS` otherwise.
- Effects, in order: `cycleCount++` → update rank → **income cap += 2×amount** → accrue product →
  deposit split → seed/pay the five earning streams.

---

## 3. Deposit split (= 100% of the entry)
| Bucket | % | Destination |
|--------|---|-------------|
| Admin | 10% | `creditBalance(adminWallet)` |
| Marketing | 5% | `creditBalance(marketingWallet)` |
| Leaders Group Sales | 5% | `creditBalance(leadersWallet)` |
| Token Liquidity | 80% | **LP active:** 40% → LP (`sweepSurplus`+`addLiquidityUSDT`, best-effort) **and** 40% → `creditBalance(liquidityWallet)`. **LP inactive:** full 80% → `creditBalance(liquidityWallet)`. |

`liquidityWallet`'s vault balance is the **reward pool** that funds §5. The 40% kept in-vault is the
"withdrawal backup."

---

## 4. Product (COCT)
`tokenBalance[user] += amount × (this entry's tier product %)` (USDT-value). Redeemed via **`claimToken()`**
(LegacyPrime `claimCashBack`/`withdrawToken` + `_deliverProduct` pattern), which zeroes the balance (CEI) then:
- **PREFERRED — swap:** if the LP manager is live AND the vault has ≥ `tokenBalance` USDT surplus, sweep that
  USDT out (`assets.sweepSurplus`), approve, and `COCTLiquidity.swapUSDTToCOCT(..., recipient=user)` under
  **try/catch** (market rate). Any unspent USDT is returned to the vault, so nothing is stranded.
- **FALLBACK — reserve:** otherwise deliver COCT from the contract's own COCT reserve at `productRate`
  (`coctOut = tokenBalance × productRate / 1e18`; default 100 → 1 USDT-value = 100 COCT at $0.01).
- Reverts `UNDELIVERABLE` (rolling back, keeping the balance) if neither path can pay.

**Product is NOT one of the five capped streams — claiming it does not touch the income cap.** Admin seeds the
reserve by transferring COCT to the rewards contract; the swap path needs the LP live + USDT surplus.

---

## 5. Ways to earn (all paid from the reward pool; each draws the payee's income cap)
1. **Direct Referral 5%** — on `activate`, the referral-tree sponsor (L1) earns `5% × amount` **instantly**.
2. **Daily Passive 1%/day** — the entry seeds the member's own `passive[]` mirror `{amount, maxPayout=2×amount}`; accrues 1%/day; claimed via `claimDailyPassive()` (**stability fee applies**, §7).
3. **Direct Passive 50%** — the referral-tree sponsor (L1) gets a `directPassive[]` mirror `{amount=50%×entry, maxPayout=2×that}`, 1%/day; claimed via `claimDirectPassive()`.
4. **Line Income 10%×10** — walk the **global one-line** up 10 levels; each upline gets a `lineIncome[]` mirror `{amount=10%×entry, maxPayout=2×that}`, 1%/day; claimed via `claimLineIncome()`.
5. **Override (rank differential)** — on `activate`, walk the **referral tree** up (depth-capped); each ancestor `U` with child `C` on the path earns `max(0, U.override% − C.override%) × amount` **instantly** (telescoping "higher-minus-lower" over group sales, event-driven per activation).

Mirror accrual (`PassiveData`, trione-style): `pending = amount × 1% × daysElapsed`, clamped to
`maxPayout − totalClaimed`. Per-array length capped by `maxPackages` to bound claim loops.

---

## 6. Income cap (single global 200% pool — countdown)
- `incomeCap[user] += 2 × amount` on every activation.
- **Drawn down by all five streams** when credited/collected: direct referral, daily passive, direct
  passive, line income, override.
- Each credit is **clamped to the remaining cap**; the excess is **forfeited** (skipped, event emitted).
- `incomeCap == 0` ⇒ account **inactive**: earns nothing (referral/override skipped; passive claims pay 0).
  A new activation re-tops the cap and reactivates.
- **Root** is excluded from all earning streams (company anchor).

---

## 7. Withdrawal
- **COC Stability Contribution** — a fee taken **only when Daily Passive is collected** (`claimDailyPassive`),
  by rank: Silver 5 / Gold 6 / Platinum 7 / Diamond 8 / Emerald 9 (%).
  **Black Diamond** is scaled by its BD cycle: 1st 10% · 2nd 15% · 3rd 20% · 4th 25% · 5th+ 30%.
  The fee is deducted from the payout and credited to `stabilityWallet`; the member receives the net.
- **Withdrawal denominations $20 / $50 / $100** — enforced in `COCTAssets`: `withdraw` accepts only the
  configured denominations (default {20, 50, 100} USDT), on top of the existing fee/cooldown. Members
  withdraw their vault balance directly via `COCTAssets.withdraw`; `rewards.sol` has no withdraw wrapper.

---

## 8. Admin / config (onlyAuth)
Wallets (`admin/marketing/leaders/liquidity/stability`), tier table (entries, product %, override %,
stability %), `dailyPassiveBps`, `passiveCapBps` (=20000), split bps, `maxPackages`, `overrideMaxDepth`,
LP manager + slippage, pause. All bounds-checked.

---

## 9. Defaults adopted (veto any before I build)
1. **Product %** uses **this entry's tier %**, not the member's rank %.
2. **Forfeited / over-cap earnings** are **skipped** (not paid, event emitted) — not routed to a pool.
3. **Root** earns nothing (excluded from all streams).
4. **Override depth cap** = configurable, default **100** levels up the referral tree.
5. **Entry is funded from the vault balance** (deposit to `COCTAssets` first) — matches the current design.
6. **Direct referral + override are instant** (draw cap at activation); the three passive streams accrue over time.
7. **Stability fee** → `stabilityWallet` (new wallet).
8. **Withdrawal denominations** — RESOLVED: enforced in `COCTAssets.withdraw` via a configurable
   denomination set (default {20, 50, 100} USDT). Withdrawal stays in the vault; rewards has no wrapper.
9. **Product redemption to COCT** — DONE: `claimToken()` swaps USDT→COCT via `COCTLiquidity.swapUSDTToCOCT`
   when the LP is live + vault has USDT surplus (funded by `sweepSurplus`, try/catch), else falls back to the
   contract's COCT reserve at `productRate` (default 100).

---

## 10. Solvency note
100% of each entry is split into the four buckets; nothing is reserved beyond the reward pool
(`liquidityWallet`, 40–80% of entries). Earning liabilities reach ≥200% of entries, so this is an
**inflow-funded / HYIP-shaped** model — reward claims pay while the pool holds funds and revert when it is
dry. Same posture as TRIONE / LegacyPrime (owner-accepted). The vault's `creditBalance` solvency guard and
`balanceTransfer` pool-draw keep the contract itself solvent (it never pays out more USDT than it holds).
