import { useCallback, useEffect, useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { readContract } from "@wagmi/core";
import { wagmiConfig } from "../lib/appkit.js";
import { shortAddr } from "../lib/format.js";
import { affiliateLink } from "../lib/affiliate.js";
import { contractsFor } from "../config/contracts.js";
import { accountsAbi, rewardsAbi } from "../config/abis.js";
import CopyButton from "../components/CopyButton.jsx";

const PAGE = 10;
const ZERO = "0x0000000000000000000000000000000000000000";
const isZero = (a) => !a || a.toLowerCase() === ZERO;

// Tier entry amounts (USD) and names, indexed [Silver..Black Diamond] — used to turn per-tier activation
// counts (rewards.getCycles) into a total activated amount + the member's highest tier (rank).
const TIER_USD = [20, 50, 100, 500, 1000, 5000];
const TIER_NAMES = ["Silver", "Gold", "Platinum", "Diamond", "Emerald", "Black Diamond"];

// Reads a member's per-tier activation counts and returns their total activated USD + highest tier reached.
function useActivated(rewards, address, chainId) {
  const { data } = useReadContract({
    address: rewards,
    abi: rewardsAbi,
    functionName: "getCycles",
    args: [address],
    chainId,
    query: { enabled: !!rewards && !!address },
  });
  const cycles = data ?? [];
  let total = 0;
  let top = -1;
  for (let i = 0; i < cycles.length; i++) {
    const n = Number(cycles[i] ?? 0n);
    total += n * TIER_USD[i];
    if (n > 0) top = i;
  }
  return { total, tier: top >= 0 ? TIER_NAMES[top] : null };
}

// The "Activated" table cell: total activated USD with the highest tier (rank) as a subtle suffix; "—" if none.
function ActivatedCell({ rewards, address, chainId }) {
  const { total, tier } = useActivated(rewards, address, chainId);
  return (
    <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
      {total > 0 ? (
        <>
          ${total.toLocaleString()}
          <span className="coc-tree__muted"> · {tier}</span>
        </>
      ) : (
        <span className="coc-tree__muted">—</span>
      )}
    </td>
  );
}

// Tree page — two genealogies for the connected wallet, both as table rows:
//   • Affiliate tree: referral tree, lazy-expanded per node (getAffiliate/getChildren).
//   • Line tree: the global one-line, walked forward from your wallet, 10 rows at a time (line linked list).
export default function Tree() {
  const { address, chainId, isConnected } = useAccount();
  const c = contractsFor(chainId);
  const [tab, setTab] = useState("affiliate"); // 'affiliate' | 'line'

  return (
    <div className="card-inner active coc-wallet-card" id="tree-card">
      <div className="row card-container">
        <div className="card-wrap col col-m-12 col-t-12 col-d-8 col-d-lg-6" data-simplebar="true">
          <div
            className="card-image col col-m-12 col-t-12 col-d-4 col-d-lg-6"
            style={{ backgroundImage: 'url("/static/media/profile.f3dc91f5255f2aa78a4f.jpg")' }}
          ></div>

          <div className="content inner-top">
            <div className="row">
              <div className="col col-m-12 col-t-12 col-d-12 col-d-lg-12">
                <div className="title-bg">Tree</div>
              </div>
            </div>
          </div>

          <div className="content coc-wallet">
            <div className="row">
              <div className="col col-m-12 col-t-12 col-d-12 col-d-lg-12">
                <div className="title">
                  <span>My</span> Network
                </div>

                <div className="cw-connect">
                  <appkit-button balance="hide"></appkit-button>
                  <appkit-network-button></appkit-network-button>
                </div>

                {!isConnected ? (
                  <div className="cw-empty card-box">
                    <div className="icon">
                      <i className="la la-sitemap"></i>
                    </div>
                    <p>Connect your wallet to view your affiliate and line trees.</p>
                  </div>
                ) : !c ? (
                  <div className="cw-empty card-box">
                    <div className="icon">
                      <i className="la la-exclamation-triangle"></i>
                    </div>
                    <p>COC is not deployed on this network. Switch to a supported network (COC Anvil / BSC).</p>
                  </div>
                ) : (
                  <>
                    <AffiliateLinkCard address={address} />

                    <div className="coc-tree__tabs">
                      <button
                        className={`cw-btn ${tab === "affiliate" ? "cw-btn--primary" : ""}`}
                        onClick={() => setTab("affiliate")}
                      >
                        Affiliate Tree
                      </button>
                      <button
                        className={`cw-btn ${tab === "line" ? "cw-btn--primary" : ""}`}
                        onClick={() => setTab("line")}
                      >
                        Line Tree
                      </button>
                    </div>

                    {tab === "affiliate" ? (
                      <AffiliateTree address={address} accounts={c.accounts} rewards={c.rewards} chainId={chainId} />
                    ) : (
                      <LineTree address={address} accounts={c.accounts} rewards={c.rewards} chainId={chainId} />
                    )}
                  </>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ------------------------------ Affiliate link ----------------------------- */
// Your shareable referral link (<origin>/#/<yourAddress>). Anyone who opens it gets you set as their
// sponsor automatically on the Account registration form.
function AffiliateLinkCard({ address }) {
  const link = affiliateLink(address);
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      /* clipboard blocked — user can still select the text */
    }
  };

  if (!link) return null;
  return (
    <div className="cw-tokens">
      <div className="cw-eyebrow">Your affiliate link</div>
      <div className="cw-token card-box" style={{ gap: 12, alignItems: "center" }}>
        <span style={{ flex: 1, minWidth: 0, wordBreak: "break-all", fontSize: 13 }} title={link}>
          {link}
        </span>
        <button type="button" className="cw-claim" onClick={copy} style={{ flexShrink: 0 }}>
          {copied ? "Copied ✓" : "Copy"}
        </button>
      </div>
      <p className="cw-modal-sub" style={{ opacity: 0.7, margin: "6px 2px 0" }}>
        Share this link — new members who open it get you set as their sponsor automatically.
      </p>
    </div>
  );
}

/* ------------------------------ Affiliate tree ----------------------------- */

function AffiliateTree({ address, accounts, rewards, chainId }) {
  return (
    <div className="cw-tokens">
      <div className="cw-eyebrow">Affiliate tree (referral)</div>
      <table className="coc-tree">
        <thead>
          <tr>
            <th>Member</th>
            <th style={{ textAlign: "right" }}>Activated</th>
            <th style={{ textAlign: "right" }}>Directs</th>
          </tr>
        </thead>
        <tbody>
          <AffNode address={address} accounts={accounts} rewards={rewards} chainId={chainId} depth={0} you />
        </tbody>
      </table>
    </div>
  );
}

// One referral-tree node. Reads its direct count always; loads children only when expanded (lazy).
function AffNode({ address, accounts, rewards, chainId, depth, you }) {
  const [open, setOpen] = useState(false);
  const [limit, setLimit] = useState(PAGE);

  const { data: aff } = useReadContract({
    address: accounts,
    abi: accountsAbi,
    functionName: "getAffiliate",
    args: [address],
    chainId,
    query: { enabled: !!accounts && !!address },
  });
  const directs = aff ? Number(aff[1]) : 0;

  const { data: kids, isLoading } = useReadContract({
    address: accounts,
    abi: accountsAbi,
    functionName: "getChildren",
    args: [address, 0n, BigInt(limit)],
    chainId,
    query: { enabled: open && directs > 0 && !!accounts },
  });
  const children = kids?.[0] ?? [];
  const total = kids ? Number(kids[1]) : directs;

  return (
    <>
      <tr>
        <td>
          <span className="coc-tree__cell" style={{ paddingLeft: depth * 18 }}>
            {directs > 0 ? (
              <button className="coc-tree__toggle" onClick={() => setOpen((o) => !o)}>
                {open ? "−" : "+"}
              </button>
            ) : (
              <span className="coc-tree__leaf">•</span>
            )}
            <span className="coc-tree__addr">
              {shortAddr(address)}
              {you && <span className="coc-tree__you"> you</span>}
            </span>
            <CopyButton value={address} />
          </span>
        </td>
        <ActivatedCell rewards={rewards} address={address} chainId={chainId} />
        <td style={{ textAlign: "right" }}>{directs}</td>
      </tr>
      {open && isLoading && children.length === 0 && (
        <tr>
          <td colSpan={3} className="coc-tree__muted" style={{ paddingLeft: (depth + 1) * 18 }}>
            Loading…
          </td>
        </tr>
      )}
      {open &&
        children.map((ch) => (
          <AffNode key={ch} address={ch} accounts={accounts} rewards={rewards} chainId={chainId} depth={depth + 1} />
        ))}
      {open && total > children.length && (
        <tr>
          <td colSpan={3} style={{ paddingLeft: (depth + 1) * 18 }}>
            <button className="coc-tree__more" onClick={() => setLimit((l) => l + PAGE)}>
              Load more ({children.length}/{total})
            </button>
          </td>
        </tr>
      )}
    </>
  );
}

/* -------------------------------- Line tree -------------------------------- */
function LineTree({ address, accounts, rewards, chainId }) {
  const [members, setMembers] = useState([]); // addresses below you, in line order
  const [cursor, setCursor] = useState(null); // last node walked (start = you)
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);

  const loadMore = useCallback(
    async (reset = false) => {
      setLoading(true);
      let node = reset ? address : cursor ?? address;
      const acc = [];
      try {
        for (let i = 0; i < PAGE; i++) {
          const res = await readContract(wagmiConfig, {
            address: accounts,
            abi: accountsAbi,
            functionName: "line",
            args: [node],
            chainId,
          });
          const child = res?.[1]; // line(node) => (parent, child)
          if (isZero(child)) break;
          acc.push(child);
          node = child;
        }
        setMembers((prev) => (reset ? acc : [...prev, ...acc]));
        setCursor(node);
        setHasMore(acc.length === PAGE); // a full page → probably more
      } finally {
        setLoading(false);
      }
    },
    [address, accounts, chainId, cursor]
  );

  // Initial load (and reset when the wallet changes).
  useEffect(() => {
    setMembers([]);
    setCursor(null);
    setHasMore(true);
    loadMore(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [address, accounts, chainId]);

  return (
    <div className="cw-tokens">
      <div className="cw-eyebrow">Line tree (global one-line, starting at you)</div>
      <table className="coc-tree">
        <thead>
          <tr>
            <th style={{ width: 48 }}>#</th>
            <th>Line member</th>
            <th style={{ textAlign: "right" }}>Activated</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td className="coc-tree__muted">0</td>
            <td>
              <span className="coc-tree__addr">
                {shortAddr(address)}
                <span className="coc-tree__you"> you</span>
              </span>
            </td>
            <ActivatedCell rewards={rewards} address={address} chainId={chainId} />
          </tr>
          {members.map((m, i) => (
            <tr key={m}>
              <td className="coc-tree__muted">{i + 1}</td>
              <td>
                <span className="coc-tree__addr">{shortAddr(m)}</span>
              </td>
              <ActivatedCell rewards={rewards} address={m} chainId={chainId} />
            </tr>
          ))}
          {members.length === 0 && !loading && (
            <tr>
              <td colSpan={3} className="coc-tree__muted">
                No members below you in the line yet.
              </td>
            </tr>
          )}
        </tbody>
      </table>
      {hasMore && (
        <button className="coc-tree__more" onClick={() => loadMore(false)} disabled={loading}>
          {loading ? "Loading…" : `Load 10 more`}
        </button>
      )}
    </div>
  );
}
