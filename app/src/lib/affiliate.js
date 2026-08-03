// Affiliate / sponsor referral-link helpers.
//
// Link format: <origin>/#/<sponsorAddress>   e.g. https://cashonchain.network/#/0xABC…  (dev: http://localhost:5173/#/0xABC…)
// Hash-based on purpose: the "#/…" fragment never reaches the server, so the link works identically on
// localhost and on the deployed apex domain WITHOUT any SPA/server rewrite. A visitor who opens such a link
// has the sponsor captured into localStorage and auto-filled on the Account registration form.
import { isAddress, getAddress } from "viem";

const SPONSOR_KEY = "coc_sponsor";

/** Build the shareable affiliate link for `address` (checksummed), or "" if `address` is missing/invalid. */
export function affiliateLink(address) {
  if (!address || !isAddress(address)) return "";
  return `${window.location.origin}/#/${getAddress(address)}`;
}

/** The stored sponsor address (checksummed), or "" if none / invalid. */
export function getStoredSponsor() {
  try {
    const v = localStorage.getItem(SPONSOR_KEY);
    return v && isAddress(v) ? getAddress(v) : "";
  } catch {
    return "";
  }
}

/** Persist a sponsor address if valid; returns the stored (checksummed) value, or "". */
export function setStoredSponsor(address) {
  try {
    if (address && isAddress(address)) {
      const a = getAddress(address);
      localStorage.setItem(SPONSOR_KEY, a);
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
