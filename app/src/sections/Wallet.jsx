import { useEffect, useState, useCallback } from "react";
import { useAccount, useDisconnect } from "wagmi";
import {
  getBalance,
  readContracts,
  sendTransaction,
  writeContract,
  waitForTransactionReceipt,
} from "@wagmi/core";
import { erc20Abi, formatUnits, parseUnits } from "viem";
import { QRCodeSVG } from "qrcode.react";
import { wagmiConfig, TOKENS } from "../lib/appkit.js";
import { amt, shortAddr, usd } from "../lib/format.js";

// Themed wallet panel — mirrors the ORBIX Wallet page (total card, receive/send, token list, disconnect)
// in the COC template's design. Adopts the same section shell (card-inner > card-container > card-wrap >
// card-image + content) as About/Resume/Contact so spacing, scroll and the side image are uniform.
// Receive / Send open as a modal that covers the whole card, dismissed by the header back button.
export default function Wallet() {
  const { address, chainId, isConnected } = useAccount();
  const { disconnect } = useDisconnect();

  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState(null);
  const [copied, setCopied] = useState(false);
  const [sheet, setSheet] = useState(null); // 'receive' | 'send' | null

  const loadBalances = useCallback(async () => {
    if (!isConnected || !address) {
      setRows([]);
      return;
    }
    setLoading(true);
    setErr(null);
    try {
      const erc20s = TOKENS.filter((t) => t.kind === "erc20");
      const [native, results] = await Promise.all([
        getBalance(wagmiConfig, { address, chainId }),
        erc20s.length
          ? readContracts(wagmiConfig, {
              allowFailure: true,
              contracts: erc20s.map((t) => ({
                address: t.address,
                abi: erc20Abi,
                functionName: "balanceOf",
                args: [address],
                chainId,
              })),
            })
          : Promise.resolve([]),
      ]);
      let i = 0;
      const out = TOKENS.map((t) => {
        let raw = 0n;
        if (t.kind === "native") raw = native.value;
        else {
          const r = results[i++];
          raw = r && r.status === "success" ? r.result : 0n;
        }
        return { ...t, amount: Number(formatUnits(raw, t.decimals)) };
      });
      setRows(out);
    } catch (e) {
      setErr(e?.shortMessage || e?.message || "Failed to load balances");
    } finally {
      setLoading(false);
    }
  }, [address, chainId, isConnected]);

  useEffect(() => {
    loadBalances();
  }, [loadBalances]);

  const usdtRow = rows.find((r) => r.symbol === "USDT");
  const total = usdtRow ? usdtRow.amount : 0;

  const copy = () => {
    if (!address) return;
    navigator.clipboard?.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <div className="card-inner active coc-wallet-card" id="wallet-card">
      <div className="row card-container">
        <div className="card-wrap col col-m-12 col-t-12 col-d-8 col-d-lg-6" data-simplebar="true">
          {/* TEMPORARY placeholder image — swap for a COC-branded asset later (matches the other pages). */}
          <div
            className="card-image col col-m-12 col-t-12 col-d-4 col-d-lg-6"
            style={{ backgroundImage: 'url("/static/media/profile4.dbb1a6c68b45964de2b0.jpg")' }}
          ></div>

          <div className="content inner-top">
            <div className="row">
              <div className="col col-m-12 col-t-12 col-d-12 col-d-lg-12">
                <div className="title-bg">Wallet</div>
              </div>
            </div>
          </div>

          <div className="content coc-wallet">
            <div className="row">
              <div className="col col-m-12 col-t-12 col-d-12 col-d-lg-12">
                <div className="title">
                  <span>Cash</span> On Chain
                </div>

                <div className="cw-connect">
                  {/* Reown AppKit web components (connect / account / network switch) */}
                  <appkit-button balance="hide"></appkit-button>
                  <appkit-network-button></appkit-network-button>
                </div>

                {!isConnected ? (
                  <div className="cw-empty card-box">
                    <div className="icon">
                      <i className="la la-credit-card"></i>
                    </div>
                    <p>Connect your wallet to view balances and to receive or send USDT / COCT.</p>
                  </div>
                ) : (
                  <>
                    <div className="cw-total card-box">
                      <div className="cw-total-label">Total balance</div>
                      <div className="cw-total-value">{loading ? "—" : `${usd(total)} USDT`}</div>
                      <div className="cw-addr">
                        <span>{shortAddr(address)}</span>
                        <button type="button" className="cw-copy" onClick={copy}>
                          {copied ? "Copied" : "Copy"}
                        </button>
                      </div>
                      <div className="cw-actions">
                        <button
                          type="button"
                          className="cw-btn cw-btn--primary"
                          onClick={() => setSheet("receive")}
                        >
                          Receive
                        </button>
                        <button type="button" className="cw-btn" onClick={() => setSheet("send")}>
                          Send
                        </button>
                      </div>
                    </div>

                    <div className="cw-tokens">
                      <div className="cw-eyebrow">
                        Assets {err && <span className="cw-err">{err}</span>}
                      </div>
                      {rows.map((r) => (
                        <div className="cw-token card-box" key={r.symbol}>
                          <span className="cw-token-sym">{r.symbol}</span>
                          <span className="cw-token-amt">{loading ? "…" : amt(r.amount)}</span>
                        </div>
                      ))}
                    </div>

                    <button
                      type="button"
                      className="cw-btn cw-btn--ghost"
                      onClick={() => disconnect()}
                    >
                      Disconnect
                    </button>
                  </>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Full-cover modal for Receive / Send — dismissed by the header back button. */}
      {sheet && (
        <div className="cw-modal coc-wallet" role="dialog" aria-modal="true">
          <div className="cw-modal-head">
            <button
              type="button"
              className="cw-modal-close"
              onClick={() => setSheet(null)}
              aria-label="Back"
            >
              <i className="la la-arrow-left"></i>
            </button>
            <span className="cw-modal-title">{sheet === "receive" ? "Receive" : "Send"}</span>
          </div>
          <div className="cw-modal-body">
            {sheet === "receive" ? (
              <div className="cw-receive">
                <p className="cw-modal-sub">
                  Scan or copy your address to receive USDT / COCT / BNB on the connected network.
                </p>
                {address && (
                  <div className="cw-qr">
                    <QRCodeSVG value={address} size={188} level="M" bgColor="#ffffff" fgColor="#0b1a08" />
                  </div>
                )}
                <p className="cw-mono cw-addr-full">{address}</p>
                <button type="button" className="cw-btn cw-btn--primary" onClick={copy}>
                  {copied ? "Copied ✓" : "Copy address"}
                </button>
              </div>
            ) : (
              <SendForm tokens={rows} chainId={chainId} onDone={loadBalances} />
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// Compact send form — native (BNB) via sendTransaction, ERC-20 (USDT/COCT) via writeContract.transfer.
function SendForm({ tokens, chainId, onDone }) {
  const [sym, setSym] = useState(tokens[0]?.symbol ?? "USDT");
  const [to, setTo] = useState("");
  const [val, setVal] = useState("");
  const [status, setStatus] = useState("idle"); // idle | pending | success | error
  const [error, setError] = useState(null);
  const token = tokens.find((t) => t.symbol === sym) ?? tokens[0];

  const submit = async (e) => {
    e.preventDefault();
    setError(null);
    setStatus("pending");
    try {
      const value = parseUnits(val, token.decimals);
      let hash;
      if (token.kind === "native") {
        hash = await sendTransaction(wagmiConfig, { to, value, chainId });
      } else {
        hash = await writeContract(wagmiConfig, {
          address: token.address,
          abi: erc20Abi,
          functionName: "transfer",
          args: [to, value],
          chainId,
        });
      }
      await waitForTransactionReceipt(wagmiConfig, { hash, chainId });
      setStatus("success");
      setTo("");
      setVal("");
      onDone?.();
    } catch (e2) {
      setError(e2?.shortMessage || e2?.message || "Transaction failed");
      setStatus("error");
    }
  };

  const busy = status === "pending";

  return (
    <form className="cw-sendform" onSubmit={submit}>
      <div className="cw-field">
        <label>Token</label>
        <select value={sym} onChange={(e) => setSym(e.target.value)} disabled={busy}>
          {tokens.map((t) => (
            <option key={t.symbol} value={t.symbol}>
              {t.symbol}
            </option>
          ))}
        </select>
      </div>
      <div className="cw-field">
        <label>Recipient</label>
        <input value={to} onChange={(e) => setTo(e.target.value)} placeholder="0x…" disabled={busy} />
      </div>
      <div className="cw-field">
        <label>Amount</label>
        <input
          value={val}
          onChange={(e) => setVal(e.target.value)}
          placeholder="0.0"
          inputMode="decimal"
          disabled={busy}
        />
      </div>
      <button type="submit" className="cw-btn cw-btn--primary" disabled={busy || !to || !val}>
        {busy ? "Sending…" : status === "success" ? "Sent ✓" : `Send ${sym}`}
      </button>
      {error && <p className="cw-err">{error}</p>}
    </form>
  );
}
