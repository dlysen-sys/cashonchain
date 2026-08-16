// "Add token to wallet" support — local memory of what the user already added, plus error triage.
//
// A dApp CANNOT ask a wallet which tokens it tracks: EIP-747 (wallet_watchAsset) is write-only and no
// RPC exposes the asset list, by design. So "is COCT already in your wallet?" is unanswerable — we
// approximate it by remembering that the user accepted the prompt here, and always leave the action
// reachable (same as PancakeSwap). Clearing site data or using another browser re-shows the prompt.

const PREFIX = "coc:addtok";

const norm = (v) => String(v ?? "").toLowerCase();

/// Key is per account AND chain: MetaMask tracks assets per account, so a second account should be
/// prompted again rather than inheriting the first account's "already added" flag.
export function tokenAddedKey(account, chainId, token) {
  return `${PREFIX}:${norm(account)}:${chainId}:${norm(token)}`;
}

export function bannerDismissedKey(account, chainId) {
  return `${PREFIX}-banner:${norm(account)}:${chainId}`;
}

// localStorage throws in private-mode Safari and when storage is disabled — never let that break the
// page; a failed read/write just means the prompt shows again next time.
function readFlag(key) {
  try {
    return window.localStorage.getItem(key) === "1";
  } catch {
    return false;
  }
}

function writeFlag(key) {
  try {
    window.localStorage.setItem(key, "1");
  } catch {
    /* storage unavailable — the prompt simply reappears later */
  }
}

export const wasTokenAdded = (account, chainId, token) => readFlag(tokenAddedKey(account, chainId, token));
export const markTokenAdded = (account, chainId, token) => writeFlag(tokenAddedKey(account, chainId, token));

export const wasBannerDismissed = (account, chainId) => readFlag(bannerDismissedKey(account, chainId));
export const markBannerDismissed = (account, chainId) => writeFlag(bannerDismissedKey(account, chainId));

/// EIP-1193 code 4001 = the user rejected the request. This must be told apart from "the wallet can't
/// do this": a user who declined on purpose should NOT then be shown the manual-add fallback.
export function isUserRejection(err) {
  const code = err?.code ?? err?.cause?.code;
  if (code === 4001) return true;
  return /user rejected|user denied|rejected the request/i.test(err?.message ?? "");
}
