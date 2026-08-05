# Cash On Chain (COC) — Milestones

**Project Status:** 🟢 ~98% — LIVE on BSC mainnet + cashonchain.network
**Last Updated:** 2026-08-06
**Next Session Focus:** Warm the LP TWAP (or seed COCT reserve + setProductRate) to finish `claimToken`; operational hardening (distinct wallets, demote old rewards, owner→multisig)
**Session Status:** CLOSED 2026-08-06 — income calculator + UI polish + TWAP fix + publish

---

## Current State (2026-08-06)
- **LIVE:** COCT peripheral contracts on BSC mainnet + frontend at **cashonchain.network** (gh-pages,
  repo `dlysen-sys/cashonchain`). dApp functional — rewards is an accounts admin.
- Full comp plan wired (register/deposit/activate, 5 reward streams, agent rewards, tree, withdraw) on the
  real-balance vault model. Subscribe now includes an **income projection calculator**.
- **Residual (~2%):** `claimToken` swap path pending LP **TWAP warm-up** (ran `growObservationCardinality(100)`;
  needs swaps + ~10 min) or interim seed-reserve + `setProductRate`. Operational: 4 distinct split wallets
  (currently owner EOA), demote old rewards `0x83Cd…` from accounts admin, owner → multisig. Source commit
  `d3474f3` local-only (site already published).

## Phase Breakdown

### ✅ Phase 1: Kickoff + scaffold
**Status:** COMPLETE
- [x] Scaffolded `projects/coc` (React 18 + Vite + theme system)
- [x] Wired build/deploy identity to COC / cashonchain.network
      (`package.json` name+homepage+deploy cname, `vite.config.js`, `index.html`, `manifest.json`, `app/README.md`)
- [x] Created archive folders `app/src/pages/archived` + `app/src/sections/archived` with the archive-on-replace README
- [x] Wrote project `CLAUDE.md`, `sessions/MILESTONES.md`, first session file
- [x] `.env.local` placeholder created (empty `GITHUB_TOKEN`, gitignored)
- [x] Kickoff logged in `decisions/log.md`
- [ ] **Define the COC product** — contracts, token, user flows (owner input needed)

### ✅ Phase 2: Content + page rebuild
**Status:** COMPLETE — COC content live (dashboard, account, subscribe, wallet, tree, income calculator)
- [ ] Rebuild placeholder pages/sections with COC content; archive each original as it's replaced
- [ ] `site.js` — COC brand, nav, social, hero
- [ ] Clean up starter assets/docs (`docs/`, placeholder media)

### ✅ Phase 3: Web3 integration
**Status:** COMPLETE — contracts on BSC mainnet, wagmi/AppKit wired, dApp functional (residual: claimToken TWAP warm-up)
- [x] COCT contract set in `contracts/` (token + accounts/assets/staking/liquidity/membership + tests); COCT token address wired (`0x13c6f832…A77`)
- [x] `accounts.sol` global one-line + `moveLine`; `rewards.sol` (`COCTRewards`) compensation-plan hub built per `docs/REWARDS.md`; `assets.sol` withdrawal denominations {20,50,100}
- [x] Mirrored to `chain/src/coc/`; Foundry tests `chain/test/coc/COCTRewards.t.sol` (10/10 pass); deployed + smoke-tested on local anvil (`chain/script/coc/Deploy.s.sol` + `deploy-local.sh`)
- [ ] Security review the COCT contracts (esp. rewards.sol inflow-funded model + wallet drain surfaces); deploy the peripheral contracts to BSC (token already live) + wire real COCTLiquidity
- [ ] wagmi + Reown AppKit (`templates/web3-integration-template.md`)
- [ ] Mirror to `chain/src/coc/` + Foundry tests; deploy to NAS anvil (dev)
- [ ] Wire dashboard/actions per `references/sops/smart-contract-integration.md`

### ✅ Phase 4: Ship
**Status:** COMPLETE — repo `dlysen-sys/cashonchain`, gh-pages live at cashonchain.network + HTTPS
- [ ] Create `dlysen` repo (suggested `dlysen/cashonchain`); PAT in `.env.local`
- [ ] `gh-pages` deploy + cPanel `dist.zip` backup
- [ ] Custom domain `cashonchain.network` + HTTPS

---

## Key Accomplishments This Session

- ✅ Kicked off a new Web3 dApp project and scaffolded it to workspace standard (React 18 + Vite + theme system)
- ✅ Wired every build/deploy identity string to cashonchain.network
- ✅ Established the archive-on-replace workflow (keep placeholder pages working, archive each as it's rebuilt)
- ✅ Locked scope via kickoff Q&A

---

## Scope locked at kickoff (2026-08-03)
- **Type:** Web3 dApp
- **Content:** keep the scaffold pages as-is; replace page-by-page and archive each original
- **Cadence:** 7-day → ship target 2026-08-10
- **Deploy:** GitHub Pages + cPanel `dist.zip`, domain cashonchain.network
- **Publish gate:** do NOT publish until the owner updates the classic GitHub PAT

---

## Known Limitations / Carryovers
1. The app still shows **placeholder/template pages** — real COC content lands in Phase 2.
2. Starter assets/docs (`docs/`, placeholder media) need cleanup during Phase 2.
3. **Contracts inherit ORBIX's audit posture.** `contracts/` is the COCT set (rebranded from ORBIX 2026-08-03, cosmetic-only). The COCT token is live on BSC mainnet; the peripheral contracts (accounts/assets/staking/liquidity/membership) are undeployed and need a compile check + fresh security review before use (see the ORBIX memories: assets.sol solvency finding, membership LP fix). The broader on-chain product (flows) is still undefined.
4. No git repo, no `.env.local` token → cannot publish (by design this session).
5. Frontend design is a commercial ThemeForest theme — license required before publishing.

---

## Deployment Readiness
### Code Quality
- [x] Frontend builds/runs as the template shell (identity wired)
- [ ] COC content in place
- [ ] Web3 layer integrated

### Documentation
- [x] Project CLAUDE.md documents the content model + archive workflow + deploy gate
- [ ] Deploy steps recorded once repo exists

### Ready for Next Phase
- [x] Scope agreed
- [ ] Product defined
- [ ] Repo + PAT in place

---

## Next Session Checklist (residual ~2%)
- [ ] Finish `claimToken`: warm the LP TWAP (a few swaps + ~10 min after `growObservationCardinality(100)`), OR seed the COCT reserve + `setProductRate` (~$0.16 → `6.135e18`); then retry `claimToken`.
- [ ] Push source commit `d3474f3` to `origin/main` if desired (gh-pages site already updated).
- [ ] Operational hardening: set 4 distinct split wallets (currently all owner EOA), demote old rewards `0x83Cd…` from accounts admin, migrate owner → multisig.

---

**Last Session:** 2026-08-06
**Project Owner:** Dangal Macatangay
**Status:** ✅ 98% — LIVE, residual operational items only
