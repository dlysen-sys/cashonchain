import { useEffect, useState } from "react";

/// Human-readable remaining time: "5h 23m 10s" / "23m 10s" / "10s".
function formatLeft(secs) {
  if (secs <= 0) return "";
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

/// Live countdown to an absolute on-chain UNIX deadline (seconds), for gating a write button so the
/// user can't fire a call the contract will revert (see the SOP's anti-spam cooldown gate).
///
/// `deadlineSec` is the contract's stored gate — e.g. assets.sol `coolDown[account]`. Pass 0/null
/// when the gate is disabled on-chain, so a stale deadline doesn't keep the button locked.
///
/// assets.sol requires `block.timestamp > coolDown[account]` — STRICTLY greater — so the unlock
/// moment is deadline + 1s, and a call at exactly the deadline still reverts COOLDOWN.
export function useCooldown(deadlineSec) {
  const deadline = deadlineSec == null ? 0 : Number(deadlineSec);
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));

  useEffect(() => {
    if (!deadline) return undefined;
    setNow(Math.floor(Date.now() / 1000)); // resync immediately when the deadline changes
    const id = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(id);
  }, [deadline]);

  const secondsLeft = deadline > 0 ? Math.max(0, deadline + 1 - now) : 0;
  const active = secondsLeft > 0;

  // NOTE: compares the browser clock against a chain timestamp. A skewed local clock shifts the
  // countdown by that skew; the contract remains the source of truth, so the tx error path still
  // has to handle a COOLDOWN revert.
  return { active, secondsLeft, label: formatLeft(secondsLeft) };
}
