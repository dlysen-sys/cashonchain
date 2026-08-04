// Affiliate / sponsor referral-link helpers.
//
// Link format: <origin>/#/<sponsorAddress>   e.g. https://cashonchain.network/#/0xABC…  (dev: http://localhost:5173/#/0xABC…)
// Hash-based on purpose: the "#/…" fragment never reaches the server, so the link works identically on
// localhost and on the deployed apex domain WITHOUT any SPA/server rewrite. A visitor who opens such a link
// has the sponsor captured into localStorage and auto-filled on the Account registration form.
import { isAddress, getAddress } from "viem";

const SPONSOR_KEY = "coc_sponsor";
// How long a captured sponsor stays valid in localStorage. After this it's treated as not-set (the
// registration field goes empty). 7 days — a typical affiliate attribution window.
const SPONSOR_TTL_MS = 7 * 24 * 60 * 60 * 1000;

/** Build the shareable affiliate link for `address` (checksummed), or "" if `address` is missing/invalid. */
export function affiliateLink(address) {
  if (!address || !isAddress(address)) return "";
  return `${window.location.origin}/#/${getAddress(address)}`;
}

/** The stored sponsor address (checksummed), or "" if none / invalid / expired. Expired or malformed
 *  records are cleared as a side effect, so the registration field falls back to empty. */
export function getStoredSponsor() {
  try {
    const raw = localStorage.getItem(SPONSOR_KEY);
    if (!raw) return "";
    const rec = JSON.parse(raw); // { addr, exp }
    if (!rec || !rec.addr || !isAddress(rec.addr) || typeof rec.exp !== "number" || Date.now() > rec.exp) {
      clearStoredSponsor(); // not-set / malformed / expired → treat as empty
      return "";
    }
    return getAddress(rec.addr);
  } catch {
    clearStoredSponsor(); // legacy plain-string value or bad JSON → drop it
    return "";
  }
}

/** Persist a sponsor address (with a TTL) if valid; returns the stored (checksummed) value, or "". */
export function setStoredSponsor(address) {
  try {
    if (address && isAddress(address)) {
      const a = getAddress(address);
      localStorage.setItem(SPONSOR_KEY, JSON.stringify({ addr: a, exp: Date.now() + SPONSOR_TTL_MS }));
      return a;
    }
  } catch {
    /* ignore */
  }
  return "";
}

/** Remove the stored sponsor. */
export function clearStoredSponsor() {
  try {
    localStorage.removeItem(SPONSOR_KEY);
  } catch {
    /* ignore */
  }
}

/**
 * If the current URL hash is an affiliate link (`#/0x…` or `#0x…`), capture the sponsor address into
 * localStorage and strip the hash from the URL (so a refresh/bookmark is clean). No-op otherwise.
 * Returns the captured (checksummed) address, or "".
 */
export function captureSponsorFromHash() {
  try {
    const m = (window.location.hash || "").match(/^#\/?(0x[0-9a-fA-F]{40})\b/);
    if (!m) return "";
    const captured = setStoredSponsor(m[1]);
    // Drop the hash without adding a history entry.
    window.history.replaceState(null, "", window.location.pathname + window.location.search);
    return captured;
  } catch {
    return "";
  }
}
