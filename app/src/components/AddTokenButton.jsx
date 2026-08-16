import { useCallback, useEffect, useState } from "react";
import { useWatchAsset } from "wagmi";
import {
  isUserRejection,
  markBannerDismissed,
  markTokenAdded,
  wasBannerDismissed,
  wasTokenAdded,
} from "../lib/watchToken.js";

// "Add to wallet" affordances for a custom BEP-20 (COCT/USDT). A wallet won't show a custom token
// until it's been added, so a user can hold COCT, see the balance here, and see nothing in MetaMask.
// EIP-747 wallet_watchAsset fixes that in one click.
//
// Note we can only OFFER, never detect: no wallet exposes its tracked-asset list (see lib/watchToken.js).

/// Shared click handler: fire wallet_watchAsset, then classify the outcome.
///   accepted        → remember it locally, flip to the "Added" tag
///   user rejected   → reset quietly; they said no, do not nag with the manual fallback
///   anything else   → the wallet can't do this (WalletConnect mobile, some SafePal flows) → manual modal
function useAddToken({ account, chainId, onAdded, onNeedManual }) {
  const { watchAssetAsync } = useWatchAsset();
  const [busy, setBusy] = useState(false);

  const add = useCallback(
    async (token) => {
      if (!token?.address) return;
      setBusy(true);
      try {
        const ok = await watchAssetAsync({
          type: "ERC20",
          options: {
            address: token.address,
            symbol: token.symbol,
            decimals: token.decimals,
            image: token.image,
          },
        });
        if (ok) {
          markTokenAdded(account, chainId, token.address);
          onAdded?.(token);
        } else {
          // Some wallets resolve false instead of throwing when they don't implement the method.
          onNeedManual?.(token);
        }
      } catch (e) {
        if (!isUserRejection(e)) onNeedManual?.(token);
      } finally {
        setBusy(false);
      }
    },
    [account, chainId, onAdded, onNeedManual, watchAssetAsync]
  );

  return { add, busy };
}

/// Compact pill on a token row. Reuses .cw-claim (row pill) / .cw-auto-tag (muted static tag) so it
/// lines up with the existing Claim / auto-credited rows.
export function AddTokenPill({ token, account, chainId, onNeedManual }) {
  const [added, setAdded] = useState(false);

  // Re-check on account/chain switch — the flag is keyed per account+chain.
  useEffect(() => {
    setAdded(token?.addable ? wasTokenAdded(account, chainId, token.address) : false);
  }, [account, chainId, token]);

  const { add, busy } = useAddToken({
    account,
    chainId,
    onAdded: () => setAdded(true),
    onNeedManual,
  });

  if (!token?.addable) return null;
  if (added) return <span className="cw-auto-tag">Added ✓</span>;

  return (
    <button type="button" className="cw-claim" onClick={() => add(token)} disabled={busy}>
      {busy ? "Adding…" : "+ Add"}
    </button>
  );
}

/// One-time banner above the asset list. Shows while at least one addable token hasn't been added on
/// this account+chain, and disappears once added or dismissed. The row pills stay as the way back.
export function AddTokenBanner({ tokens, account, chainId, onNeedManual }) {
  const addable = tokens.filter((t) => t.addable && t.address);
  const [hidden, setHidden] = useState(true);

  useEffect(() => {
    if (!account || !addable.length) {
      setHidden(true);
      return;
    }
    const allAdded = addable.every((t) => wasTokenAdded(account, chainId, t.address));
    setHidden(allAdded || wasBannerDismissed(account, chainId));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account, chainId, tokens]);

  const { add, busy } = useAddToken({
    account,
    chainId,
    onAdded: () => setHidden(true),
    onNeedManual,
  });

  if (hidden || !addable.length) return null;

  // Lead with the project's own token — that's the one wallets won't recognise.
  const primary = addable.find((t) => t.symbol === "COCT") ?? addable[0];

  const dismiss = () => {
    markBannerDismissed(account, chainId);
    setHidden(true);
  };

  return (
    <div className="cw-addbanner card-box">
      <div className="cw-addbanner__text">
        <strong>Not seeing {primary.symbol} in your wallet?</strong>
        <span>Add the token so your balance shows up in MetaMask, SafePal or Trust.</span>
      </div>
      <div className="cw-addbanner__actions">
        <button type="button" className="cw-claim" onClick={() => add(primary)} disabled={busy}>
          {busy ? "Adding…" : `Add ${primary.symbol}`}
        </button>
        <button type="button" className="cw-addbanner__close" onClick={dismiss} aria-label="Dismiss">
          <i className="la la-times"></i>
        </button>
      </div>
    </div>
  );
}
