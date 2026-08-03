# Cash On Chain (COC) — Development Guide

**Status:** 🟡 Phase 1 — kicked off 2026-08-03 (not yet published)
**Type:** Web3 dApp (frontend + smart-contract integration)
**Tech Stack:** React 18 + Vite 5 · react-router-dom · react-tabs · vanilla CSS theme system · (Web3 layer TBD — wagmi/Reown, BSC)
**Domain:** https://cashonchain.network
**Ship Target:** 2026-08-10 (7-day cadence)

## Overview
Cash On Chain (COC) is a Web3 dApp. The frontend is scaffolded on the workspace's standard
React 18 + Vite shell and CSS theme system; the project starts with placeholder pages that get
replaced by real COC content **page-by-page**, archiving each scaffold original as it is rebuilt.
The wallet + smart-contract layer is layered on top. The specific on-chain product (contracts,
token, flows) is still to be defined with the owner.

## Repository Layout
```
projects/coc/
  CLAUDE.md      # this guide
  sessions/      # session notes + MILESTONES.md (source of truth)
  docs/          # content briefs, deploy notes (starter files — clean up during Phase 2)
  app/           # React 18 + Vite frontend
  contracts/     # COCT Solidity contracts — token (coctoken.sol) + accounts/assets/staking/liquidity/membership + tests (see "Web3 layer")
  .env.local     # GITHUB_TOKEN placeholder (gitignored) — paste classic PAT before publishing
```
Frontend commands run from `app/` (`cd app && npm run dev|build|preview`).

## Archive-on-replace content model
The project starts on the workspace template shell with placeholder pages so the app builds/runs
from day one. As each page is rebuilt for COC, move the original into an archive folder instead
of deleting it:
- page components → `app/src/pages/archived/`
- section bodies (`*.html`) + wrappers → `app/src/sections/archived/`

Nothing in `archived/` is imported by the live app. See `app/src/pages/archived/README.md`.

## Content model (where content lives)
| Want to change… | Edit |
|-----------------|------|
| Name, typing roles, nav, social links, hero media | `app/src/data/site.js` |
| A section's body (text, cards, images) | `app/src/sections/<name>.html` (faithful, minified template markup) |
| Accent colors | `app/public/css/theme-colors/*.css` + `themeColors` in `site.js` |
| Global layout / fonts | `app/public/css/styles.css` |

Section bodies are **static HTML imported with Vite `?raw`** and injected via
`dangerouslySetInnerHTML` — edit surgically (targeted string replacement), don't reformat
whole files, and never inject user-supplied HTML into them once a backend exists.

## Web3 layer
- **Contracts (`projects/coc/contracts/`):** the COCT contract set — `coctoken.sol` (COCToken,
  BEP20 "COC TOKEN"/"COCT", fixed 1B, renounced) plus `accounts.sol` (COCTAccounts),
  `assets.sol` (COCTAssets), `staking.sol` (COCTStaking), `liquidity.sol` (COCTLiquidity),
  `membership.sol` (COCTMembership), and `test/COCT*.t.sol`. Rebranded from the ORBIX set on
  2026-08-03 (cosmetic-only — identifiers/strings/banners + token address; no logic change).
- **`rewards.sol` (`COCTRewards`)** is the active compensation-plan hub — spec in `docs/REWARDS.md`
  (6 tiers, single 200% income cap, mirror-tranche passives, rank-differential override, stability fees;
  reward pool = `liquidityWallet` vault balance). `membership.sol` is superseded (left in place, unused).
  rewards.sol must be registered via `accounts.addAdmin`. `assets.sol` enforces withdrawal denominations
  (default {20,50,100} USDT). Compiles clean; not yet tested/mirrored/deployed.
- **COCT token is LIVE on BSC mainnet at `0x13c6f832A8eA9D450FBc04c73b59D2A66ae12A77`** — wired
  as the staking/reward-token constant in `staking.sol` + `liquidity.sol`. The peripheral
  contracts are **not deployed yet**.
- ⚠ **Before deploying the peripheral contracts:** they inherit ORBIX's audit posture (see the
  ORBIX memories — assets.sol solvency finding, membership LP fix, accounts frozen). Needed:
  a compile check (mirror to `chain/src/coc/` + `forge build`), confirm `coctoken.sol`
  byte-matches the BscScan-verified deployed source, and a fresh security review.
- Add the wallet + contract stack per `templates/web3-integration-template.md` (wagmi +
  Reown AppKit) and invoke the `/blockchain-developer` skill before any Solidity/Web3 work.
- Smart-contract dev/test goes in the shared Foundry workspace: `chain/src/coc/`,
  `chain/test/coc/`, `chain/script/coc/` (see root `CLAUDE.md` → "Blockchain Testing").
- Local dev against the NAS anvil (`http://192.168.100.79:8545`, chainId 31337) via
  `templates/local-chain-template.md`; mind the local-anvil dApp browser gotchas
  (PNA→Vite `/rpc` proxy, single-chain wagmi).

## Deployment (DO NOT PUBLISH YET)
- **Primary:** GitHub Pages via `gh-pages` → **https://cashonchain.network**.
  Deploy with `cd app && npm run deploy` (`--cname cashonchain.network`).
- **Backup:** `dist.zip` for cPanel upload via the shared `tools/package-cpanel.sh`
  (npm `postbuild` hook; needed because the SMB workspace forces `0700` perms).
- Vite `base` is `/` (apex/custom domain).
- **Gate:** publishing is blocked until (1) a dedicated GitHub repo exists under `dlysen` and
  (2) the owner pastes an **updated classic GitHub PAT** into `projects/coc/.env.local` as
  `GITHUB_TOKEN`. Push without leaking the token into `.git/config`:
  `B64=$(printf 'dlysen:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n'); git -c http.extraheader="Authorization: Basic $B64" push origin main`

## GitHub Repository Setup (pending)
- Repo: **not yet created** — dedicated repo under `dlysen` (suggested `dlysen/cashonchain`),
  linked to `projects/coc/` (repo root = project root, so `app/` is a subfolder).
- Classic PAT → `projects/coc/.env.local` as `GITHUB_TOKEN` (gitignored). Owner will supply an
  updated token before first publish.

## Phases
### Phase 1: Kickoff + scaffold 🟡 (this session)
- [x] Scaffold `projects/coc` (React 18 + Vite + theme system)
- [x] Wire build/deploy identity to COC / cashonchain.network
- [x] Archive folders + archive-on-replace workflow
- [x] Project CLAUDE.md + sessions/MILESTONES.md + first session file
- [x] Kickoff logged in `decisions/log.md`
- [ ] Define the COC product (contracts, token, user flows) with the owner

### Phase 2: Content + page rebuild ⏳
- [ ] Replace placeholder pages/sections with COC content (archive each original as it's replaced)
- [ ] `site.js` brand/nav/social for COC
- [ ] Clean up starter assets/docs (`docs/`, placeholder media)

### Phase 3: Web3 integration ⏳
- [ ] Add wagmi + Reown AppKit (`templates/web3-integration-template.md`)
- [ ] COC contract(s) in `chain/src/coc/` + Foundry tests; deploy to NAS anvil for dev
- [ ] Wire dashboard/actions per `references/sops/smart-contract-integration.md`

### Phase 4: Ship ⏳ (gated on repo + updated PAT)
- [ ] Create `dlysen` repo; PAT in `.env.local`
- [ ] `gh-pages` deploy + cPanel `dist.zip` backup
- [ ] Custom domain `cashonchain.network` + HTTPS

## Current State
Frontend scaffolded and wired to cashonchain.network; builds/runs as the template shell. Phase 2
started: the **Contact tab was archived and replaced with a web3 Wallet page** (`sections/Wallet.jsx`,
Reown AppKit + wagmi via `src/lib/appkit.js`; nav is the react-tabs TabList in `pages/HomeLayout.jsx`).
Other pages are still placeholder template content. No git repo yet, nothing published. `contracts/` holds the COCT contract set
(rebranded from ORBIX 2026-08-03); the COCT token is live on BSC mainnet, the peripheral contracts
are undeployed and need a compile check + security review before use (see "Web3 layer").

## License note
The frontend design is the commercial ThemeForest theme "Patrick — Personal CV/vCard React
Template" (item 35737202). Buy a license before publishing anything derived from it.

## Next Phase
Define the COC product with the owner, then begin Phase 2 (page-by-page rebuild) and the Web3
layer.
