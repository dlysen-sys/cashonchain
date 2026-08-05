import { useEffect, useState } from "react";
import { useAccount, useReadContracts } from "wagmi";
import { useNavigate } from "react-router-dom";
import { writeContract, waitForTransactionReceipt, readContract } from "@wagmi/core";
import { erc20Abi, formatUnits, parseUnits } from "viem";
import { wagmiConfig, TOKENS } from "../lib/appkit.js";
import { amt } from "../lib/format.js";
import { contractsFor } from "../config/contracts.js";
import { accountsAbi, rewardsAbi, assetsAbi } from "../config/abis.js";

const USDT = TOKENS.find((t) => t.symbol === "USDT").address;

const TIERS = [
  { name: "Silver", amount: 20, token: "1% token", note: "5 cycles" },
  { name: "Gold", amount: 50, token: "1% token", note: "5 cycles · 1% override" },
  { name: "Platinum", amount: 100, token: "1% token", note: "5 cycles · 2% override" },
  { name: "Diamond", amount: 500, token: "1% token", note: "5 cycles · 3% override" },
  { name: "Emerald", amount: 1000, token: "1% token", note: "5 cycles · 4% override" },
  { name: "Black Diamond", amount: 5000, token: "1% token", note: "unlimited · 5% override" },
];

const fmt = (bi) => amt(Number(formatUnits(bi ?? 0n, 18)));
const prettyErr = (e) =>
  e?.name === "UserRejectedRequestError" || /reject|denied/i.test(e?.message || "")
    ? "You rejected the request in your wallet."
    : e?.shortMessage || e?.message || "Transaction failed";

// Subscribe / entry packages — gated on registration (unregistered wallets are sent to /account).
// Deposit USDT into the vault, then activate a tier (rewards.activate). Uses the SOP contract pattern.
export default function Subscribe() {
  const { address, chainId, isConnected } = useAccount();
  const c = contractsFor(chainId);
  const navigate = useNavigate();

  const { data, refetch } = useReadContracts({
    contracts:
      address && c
        ? [
            { address: c.accounts, abi: accountsAbi, functionName: "isUser", args: [address], chainId },
            { address: c.assets, abi: assetsAbi, functionName: "balanceOf", args: [address, USDT], chainId },
            { address: USDT, abi: erc20Abi, functionName: "balanceOf", args: [address], chainId },
            { address: c.rewards, abi: rewardsAbi, functionName: "getUser", args: [address], chainId },
            { address: c.rewards, abi: rewardsAbi, functionName: "getCycles", args: [address], chainId },
          ]
        : [],
    query: { enabled: !!address && !!c },
  });
  const isUser = data?.[0]?.result;
  const vaultUsdt = data?.[1]?.result ?? 0n;
  const walletUsdt = data?.[2]?.result ?? 0n;
  const rw = data?.[3]?.result; // rewards.getUser (activated, rank, …)
  const cycles = data?.[4]?.result ?? []; // per-tier activation counts [Silver..BD]
  // Highest tier ever activated; -1 when never activated (so no tier is "below" it).
  const currentRank = rw?.activated ? Number(rw.rank) : -1;

  // Registration required — send unregistered wallets to the Account page to register first.
  useEffect(() => {
    if (isConnected && c && isUser === false) navigate("/account");
  }, [isConnected, c, isUser, navigate]);

  const [busyKey, setBusyKey] = useState(null);
  const [msg, setMsg] = useState(null);
  const [depositAmt, setDepositAmt] = useState("");

  const doDeposit = async () => {
    const n = Number(depositAmt);
    if (!n || n <= 0) return setMsg({ type: "error", text: "Enter a valid amount." });
    setBusyKey("deposit");
    setMsg(null);
    try {
      const wei = parseUnits(depositAmt, 18);
      // approve only if needed (SOP Pattern 4: approve → action)
      const allowance = await readContract(wagmiConfig, {
        address: USDT,
        abi: erc20Abi,
        functionName: "allowance",
        args: [address, c.assets],
        chainId,
      });
      if (allowance < wei) {
        const ah = await writeContract(wagmiConfig, {
          address: USDT,
          abi: erc20Abi,
          functionName: "approve",
          args: [c.assets, wei],
          chainId,
        });
        await waitForTransactionReceipt(wagmiConfig, { hash: ah, chainId });
      }
      const dh = await writeContract(wagmiConfig, {
        address: c.assets,
        abi: assetsAbi,
        functionName: "deposit",
        args: [USDT, wei],
        chainId,
      });
      await waitForTransactionReceipt(wagmiConfig, { hash: dh, chainId });
      setMsg({ type: "success", text: `Deposited ${depositAmt} USDT to your vault.` });
      setDepositAmt("");
      refetch();
    } catch (e) {
      setMsg({ type: "error", text: prettyErr(e) });
    } finally {
      setBusyKey(null);
    }
  };

  const doActivate = async (tier) => {
    setBusyKey(`t${tier.amount}`);
    setMsg(null);
    try {
      const wei = parseUnits(String(tier.amount), 18); // convert at the last moment (SOP bridge)
      const h = await writeContract(wagmiConfig, {
        address: c.rewards,
        abi: rewardsAbi,
        functionName: "activate",
        args: [wei],
        chainId,
      });
      await waitForTransactionReceipt(wagmiConfig, { hash: h, chainId });
      setMsg({ type: "success", text: `Activated ${tier.name} ($${tier.amount}).` });
      refetch();
    } catch (e) {
      setMsg({ type: "error", text: prettyErr(e) });
    } finally {
      setBusyKey(null);
    }
  };

  return (
    <div className="card-inner active coc-wallet-card" id="subscribe-card">
      <div className="row card-container">
        <div className="card-wrap col col-m-12 col-t-12 col-d-8 col-d-lg-6" data-simplebar="true">
          <div
            className="card-image col col-m-12 col-t-12 col-d-4 col-d-lg-6"
            style={{ backgroundImage: 'url("/static/media/profile2.8c37e2bf24adf94ad8cc.jpg")' }}
          ></div>

          <div className="content inner-top">
            <div className="row">
              <div className="col col-m-12 col-t-12 col-d-12 col-d-lg-12">
                <div className="title-bg">Subscribe</div>
              </div>
            </div>
          </div>

          <div className="content coc-wallet">
            <div className="row">
              <div className="col col-m-12 col-t-12 col-d-12 col-d-lg-12">
                <div className="title">
                  <span>Entry</span> Packages
                </div>

                <div className="cw-connect">
                  <appkit-button balance="hide"></appkit-button>
                  <appkit-network-button></appkit-network-button>
                </div>

                {!isConnected ? (
                  <div className="cw-empty card-box">
                    <div className="icon">
                      <i className="la la-shopping-cart"></i>
                    </div>
                    <p>Connect your wallet to buy an entry package.</p>
                  </div>
                ) : !c ? (
                  <div className="cw-empty card-box">
                    <div className="icon">
                      <i className="la la-exclamation-triangle"></i>
                    </div>
                    <p>COC is not deployed on this network. Switch to a supported network (COC Anvil / BSC).</p>
                  </div>
                ) : isUser === undefined ? (
                  <div className="cw-empty card-box">
                    <p>Loading…</p>
                  </div>
                ) : isUser === false ? (
                  <div className="cw-empty card-box">
                    <p>You're not registered — taking you to the Account page to register…</p>
                  </div>
                ) : (
                  <>
                    <div className="cw-total card-box">
                      <div className="cw-total-label">Vault balance (funds your entries)</div>
                      <div className="cw-total-value">{fmt(vaultUsdt)} USDT</div>
                      <div className="cw-addr">
                        <span>Wallet: {fmt(walletUsdt)} USDT</span>
                      </div>
                      <div className="cw-field" style={{ marginTop: 14 }}>
                        <label>Deposit USDT to your vault</label>
                        <input
                          value={depositAmt}
                          onChange={(e) => setDepositAmt(e.target.value)}
                          placeholder="e.g. 100"
                          inputMode="decimal"
                          disabled={busyKey === "deposit"}
                        />
                      </div>
                      <button
                        type="button"
                        className="cw-btn cw-btn--primary"
                        style={{ width: "100%" }}
                        disabled={busyKey === "deposit" || !depositAmt}
                        onClick={doDeposit}
                      >
                        {busyKey === "deposit" ? "Depositing…" : "Deposit"}
                      </button>
                    </div>

                    <div className="cw-tokens">
                      <div className="cw-eyebrow">Entry packages</div>
                      {TIERS.map((t, i) => {
                        const wei = parseUnits(String(t.amount), 18);
                        const enough = vaultUsdt >= wei;
                        const busy = busyKey === `t${t.amount}`;
                        const rankLocked = currentRank === 5 && i < 5; // Black Diamond rank locks every lower tier
                        const cycleLocked = i !== 5 && Number(cycles[i] ?? 0) >= 5; // non-BD 5-cycle cap
                        const disabled = busy || rankLocked || cycleLocked || !enough;
                        const label = busy
                          ? "Activating…"
                          : rankLocked
                          ? "Locked"
                          : cycleLocked
                          ? "Max cycles"
                          : enough
                          ? "Activate"
                          : "Fund vault";
                        return (
                          <div className="cw-token card-box" key={t.amount} style={rankLocked || cycleLocked ? { opacity: 0.55 } : undefined}>
                            <span className="cw-token-sym">
                              {t.name}
                              <span
                                style={{ display: "block", fontSize: 12, opacity: 0.7, fontWeight: 400 }}
                              >
                                ${t.amount} · {t.token} · {t.note}
                              </span>
                            </span>
                            <button
                              type="button"
                              className="cw-btn cw-btn--primary"
                              style={{ flex: "0 0 auto", minWidth: 112 }}
                              disabled={disabled}
                              onClick={() => doActivate(t)}
                            >
                              {label}
                            </button>
                          </div>
                        );
                      })}
                    </div>

                    {msg && (
                      <p
                        className={msg.type === "error" ? "cw-err" : ""}
                        style={{
                          marginTop: 12,
                          color: msg.type === "success" ? "var(--cw-accent)" : undefined,
                        }}
                      >
                        {msg.text}
                      </p>
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
