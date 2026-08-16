import { useEffect, useState } from "react";
import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { writeContract, waitForTransactionReceipt, readContract } from "@wagmi/core";
import { erc20Abi, formatUnits, isAddress, parseUnits } from "viem";
import { wagmiConfig, TOKENS } from "../lib/appkit.js";
import { shortAddr, amt } from "../lib/format.js";
import MembershipCard, { addrToCardId } from "../components/MembershipCard.jsx";
import { contractsFor } from "../config/contracts.js";
import { accountsAbi, rewardsAbi, assetsAbi } from "../config/abis.js";
import { getStoredSponsor, clearStoredSponsor } from "../lib/affiliate.js";

const RANKS = ["Silver", "Gold", "Platinum", "Diamond", "Emerald", "Black Diamond"];
const MIN_DEPOSIT = 20; // USDT — smallest membership tier; block anything below this in the UI
const REGISTER_ENTRY = 20; // USDT — lowest-tier entry pulled into the Funding Wallet on register()
const USDT = TOKENS.find((t) => t.symbol === "USDT").address;
const COCT = TOKENS.find((t) => t.symbol === "COCT").address;
const ZERO = "0x0000000000000000000000000000000000000000";

// bigint (18-dp) → readable string
const fmt = (bi) => amt(Number(formatUnits(bi ?? 0n, 18)));

// Account page — reads the COC contracts (SOP): unregistered wallets get the registration panel;
// registered wallets get their account info + vault balances. Themed with the shared .coc-wallet styles.
export default function Account() {
  const { address, chainId, isConnected } = useAccount();
  const c = contractsFor(chainId); // null on an unsupported network

  // ---- reads ----
  const { data: isUser, refetch: refetchIsUser } = useReadContract({
    address: c?.accounts,
    abi: accountsAbi,
    functionName: "isUser",
    args: [address],
    chainId,
    query: { enabled: !!address && !!c },
  });
  const { data: info, refetch: refetchInfo } = useReadContracts({
    contracts:
      address && c && isUser === true
        ? [
            { address: c.rewards, abi: rewardsAbi, functionName: "getUser", args: [address], chainId },
            { address: c.accounts, abi: accountsAbi, functionName: "getUser", args: [address], chainId },
            { address: c.assets, abi: assetsAbi, functionName: "balanceOf", args: [address, USDT], chainId },
            { address: c.assets, abi: assetsAbi, functionName: "balanceOf", args: [address, COCT], chainId },
            { address: USDT, abi: erc20Abi, functionName: "balanceOf", args: [address], chainId },
            { address: c.rewards, abi: rewardsAbi, functionName: "overrideTotal", args: [address], chainId },
            { address: c.rewards, abi: rewardsAbi, functionName: "directReferralTotal", args: [address], chainId },
            { address: c.rewards, abi: rewardsAbi, functionName: "agentRewards", args: [address], chainId },
            { address: c.rewards, abi: rewardsAbi, functionName: "dailyPassiveTotal", args: [address], chainId },
            { address: c.rewards, abi: rewardsAbi, functionName: "directPassiveTotal", args: [address], chainId },
            { address: c.rewards, abi: rewardsAbi, functionName: "lineIncomeTotal", args: [address], chainId },
          ]
        : [],
    // Re-read every 15s so accruing pending rewards (daily/direct/line) tick up without a manual reload.
    query: { enabled: !!address && !!c && isUser === true, refetchInterval: 15_000 },
  });

  const rw = info?.[0]?.result; // rewards.getUser
  const ac = info?.[1]?.result; // accounts.getUser
  const usdtVault = info?.[2]?.result ?? 0n;
  const coctVault = info?.[3]?.result ?? 0n;
  const walletUsdt = info?.[4]?.result ?? 0n; // USDT in the wallet (not the vault)
  const overrideEarned = info?.[5]?.result ?? 0n; // lifetime override commission (paid to vault)
  const directReferralEarned = info?.[6]?.result ?? 0n; // lifetime direct-referral commission (paid to vault)
  const agentRewards = info?.[7]?.result ?? 0n; // accrued agent reward, claimed to wallet
  const dailyPassiveEarned = info?.[8]?.result ?? 0n; // lifetime daily-passive collected
  const directPassiveEarned = info?.[9]?.result ?? 0n; // lifetime direct-passive collected
  const lineIncomeEarned = info?.[10]?.result ?? 0n; // lifetime line-income collected
  // Total income rewards = sum of the five earning streams (agent reward is separate).
  const totalIncome =
    directReferralEarned + overrideEarned + dailyPassiveEarned + directPassiveEarned + lineIncomeEarned;

  // ---- register (write) ----
  const [sponsor, setSponsor] = useState("");
  const [fromReferral, setFromReferral] = useState(false); // sponsor auto-filled from an affiliate link
  const [status, setStatus] = useState("idle"); // idle | pending | success | error
  const [error, setError] = useState(null);
  const [txHash, setTxHash] = useState(undefined);
  const { writeContractAsync } = useWriteContract();
  const { isSuccess: txMined } = useWaitForTransactionReceipt({
    hash: txHash,
    chainId,
    query: { enabled: !!txHash },
  });

  // Auto-fill the sponsor field ONLY from a valid, non-expired affiliate-link sponsor (localStorage).
  // If none is set (or it expired), the field stays EMPTY — no company-root fallback. A self-referral
  // (stored sponsor == your own wallet) is invalid, so it's ignored and cleared.
  useEffect(() => {
    if (sponsor) return;
    const stored = getStoredSponsor(); // "" when not-set or expired (and clears expired records)
    if (!stored) return; // leave the field empty
    if (address && stored.toLowerCase() === address.toLowerCase()) {
      clearStoredSponsor(); // can't sponsor yourself → keep the field empty
      return;
    }
    setSponsor(stored);
    setFromReferral(true);
  }, [address]); // eslint-disable-line react-hooks/exhaustive-deps

  // If the connected wallet is already registered, the stored sponsor is moot — delete it.
  useEffect(() => {
    if (isUser === true) clearStoredSponsor();
  }, [isUser]);

  // Once the register tx mines, flip to the account view and clear the used sponsor link.
  useEffect(() => {
    if (txMined) {
      setStatus("success");
      clearStoredSponsor();
      refetchIsUser();
      refetchInfo?.();
    }
  }, [txMined]); // eslint-disable-line react-hooks/exhaustive-deps

  const register = async (e) => {
    e.preventDefault();
    setError(null);
    if (!isConnected) return setError("Connect your wallet first.");
    if (!c) return setError("Switch your wallet to a supported network (COC Anvil / BSC).");
    if (!isAddress(sponsor)) return setError("Enter a valid sponsor address.");
    setStatus("pending");
    try {
      // Registration pulls the lowest-tier entry (REGISTER_ENTRY USDT) into the Funding Wallet, so the
      // wallet must hold it and have approved the vault. Ensure both, then register.
      const entryWei = parseUnits(String(REGISTER_ENTRY), 18);
      const bal = await readContract(wagmiConfig, {
        address: USDT, abi: erc20Abi, functionName: "balanceOf", args: [address], chainId,
      });
      if (bal < entryWei) throw new Error(`Registration requires ${REGISTER_ENTRY} USDT in your wallet.`);
      const allowance = await readContract(wagmiConfig, {
        address: USDT, abi: erc20Abi, functionName: "allowance", args: [address, c.assets], chainId,
      });
      if (allowance < entryWei) {
        const ah = await writeContract(wagmiConfig, {
          address: USDT, abi: erc20Abi, functionName: "approve", args: [c.assets, entryWei], chainId,
        });
        await waitForTransactionReceipt(wagmiConfig, { hash: ah, chainId });
      }
      // useWriteContract uses the provider's connected connector; chainId makes it switch/prompt if needed.
      const hash = await writeContractAsync({
        address: c.rewards,
        abi: rewardsAbi,
        functionName: "register",
        args: [sponsor],
        chainId,
      });
      setTxHash(hash); // mining tracked by useWaitForTransactionReceipt above
    } catch (e2) {
      const rejected =
        e2?.name === "UserRejectedRequestError" || /reject|denied/i.test(e2?.message || "");
      setError(
        rejected
          ? "You rejected the request in your wallet."
          : e2?.shortMessage || e2?.message || "Registration failed"
      );
      setStatus("error");
    }
  };
  const busy = status === "pending";

  // ---- deposit / withdraw (assets.sol) ----
  const [sheet, setSheet] = useState(null); // 'deposit' | 'withdraw' | null
  const [depAmt, setDepAmt] = useState("");
  const [txBusy, setTxBusy] = useState(false);
  const [txMsg, setTxMsg] = useState(null); // { type: 'success'|'error', text }

  const prettyErr = (e) =>
    e?.name === "UserRejectedRequestError" || /reject|denied/i.test(e?.message || "")
      ? "You rejected the request in your wallet."
      : e?.shortMessage || e?.message || "Transaction failed";

  const openSheet = (which) => {
    setSheet(which);
    setTxMsg(null);
    setDepAmt("");
  };

  const doDeposit = async () => {
    const n = Number(depAmt);
    if (!Number.isFinite(n) || n <= 0)
      return setTxMsg({ type: "error", text: "Enter a valid amount." });
    if (n < MIN_DEPOSIT)
      return setTxMsg({ type: "error", text: `Minimum deposit is ${MIN_DEPOSIT} USDT.` });
    const wei = parseUnits(depAmt, 18); // convert at the last moment (SOP bridge)
    if (wei > walletUsdt)
      return setTxMsg({ type: "error", text: "Not enough USDT in your wallet." });
    setTxBusy(true);
    setTxMsg(null);
    try {
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
      setTxMsg({ type: "success", text: `Deposited ${depAmt} USDT to your Funding Wallet.` });
      setDepAmt("");
      refetchInfo?.();
    } catch (e) {
      setTxMsg({ type: "error", text: prettyErr(e) });
    } finally {
      setTxBusy(false);
    }
  };

  const doWithdraw = async (denom) => {
    setTxBusy(true);
    setTxMsg(null);
    try {
      const wei = parseUnits(String(denom), 18);
      const h = await writeContract(wagmiConfig, {
        address: c.assets,
        abi: assetsAbi,
        functionName: "withdraw",
        args: [USDT, wei],
        chainId,
      });
      await waitForTransactionReceipt(wagmiConfig, { hash: h, chainId });
      setTxMsg({ type: "success", text: `Withdrew $${denom} USDT to your wallet.` });
      refetchInfo?.();
    } catch (e) {
      setTxMsg({ type: "error", text: prettyErr(e) });
    } finally {
      setTxBusy(false);
    }
  };

  // ---- claim accrued income (rewards.sol) ----
  const [claiming, setClaiming] = useState(null); // fn name in-flight, or null
  const [claimMsg, setClaimMsg] = useState(null); // { type, text }
  const doClaim = async (fn, label) => {
    if (!c) return;
    setClaiming(fn);
    setClaimMsg(null);
    try {
      const h = await writeContract(wagmiConfig, {
        address: c.rewards,
        abi: rewardsAbi,
        functionName: fn,
        chainId,
      });
      await waitForTransactionReceipt(wagmiConfig, { hash: h, chainId });
      setClaimMsg({ type: "success", text: `Claimed ${label}.` });
      refetchInfo?.();
    } catch (e) {
      setClaimMsg({ type: "error", text: prettyErr(e) });
    } finally {
      setClaiming(null);
    }
  };

  const active = rw ? rw.incomeCap > 0n : false;
  const rankName = rw?.activated ? RANKS[Number(rw.rank)] ?? "—" : "Not activated";

  // Deposit input validation (client-side gate to cut human error before a wallet prompt).
  const depNum = Number(depAmt);
  let depWei = 0n;
  try {
    depWei = depAmt ? parseUnits(depAmt, 18) : 0n;
  } catch {
    depWei = -1n; // unparseable input
  }
  const depError = !depAmt
    ? null
    : !Number.isFinite(depNum) || depWei < 0n
    ? "Enter a valid amount."
    : depNum < MIN_DEPOSIT
    ? `Minimum deposit is ${MIN_DEPOSIT} USDT.`
    : depWei > walletUsdt
    ? "Not enough USDT in your wallet."
    : null;
  const depOk = !!depAmt && !depError;

  return (
    <div className="card-inner active coc-wallet-card" id="account-card">
      <div className="row card-container">
        <div className="card-wrap col col-m-12 col-t-12 col-d-8 col-d-lg-6" data-simplebar="true">
          {/* TEMPORARY placeholder image — swap for a COC-branded asset later. */}
          <div
            className="card-image col col-m-12 col-t-12 col-d-4 col-d-lg-6"
            style={{ backgroundImage: 'url("/static/media/profile3.0adab060c3a8114a1fbd.jpg")' }}
          ></div>

          <div className="content inner-top">
            <div className="row">
              <div className="col col-m-12 col-t-12 col-d-12 col-d-lg-12">
                <div className="title-bg">Account</div>
              </div>
            </div>
          </div>

          <div className="content coc-wallet">
            <div className="row">
              <div className="col col-m-12 col-t-12 col-d-12 col-d-lg-12">
                <div className="title">
                  <span>Your</span> Account
                </div>

                <div className="cw-connect">
                  <appkit-button balance="hide"></appkit-button>
                  <appkit-network-button></appkit-network-button>
                </div>

                {!isConnected ? (
                  <div className="cw-empty card-box">
                    <div className="icon">
                      <i className="la la-user"></i>
                    </div>
                    <p>Connect your wallet to register or view your account.</p>
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
                    <p>Loading account…</p>
                  </div>
                ) : !isUser ? (
                  /* ---------- Registration panel (unregistered) ---------- */
                  <form className="cw-sendform" onSubmit={register}>
                    <div className="cw-total card-box">
                      <div className="cw-total-label">Not registered</div>
                      <div className="cw-total-value" style={{ fontSize: 20 }}>
                        Join Cash On Chain
                      </div>
                      <p className="cw-modal-sub" style={{ opacity: 0.75 }}>
                        Registration includes a {REGISTER_ENTRY} USDT entry, deposited to your Funding Wallet
                        (approve the vault when prompted). Then activate a tier from that balance.
                      </p>
                    </div>
                    <div className="cw-field">
                      <label>Sponsor address</label>
                      <input
                        value={sponsor}
                        onChange={(e) => {
                          setSponsor(e.target.value);
                          setFromReferral(false);
                        }}
                        placeholder="0x…"
                        disabled={busy}
                      />
                      {fromReferral && (
                        <p className="cw-modal-sub" style={{ color: "var(--cw-accent)", margin: "6px 2px 0" }}>
                          <i className="la la-link"></i> Sponsor pre-filled from your referral link.
                        </p>
                      )}
                    </div>
                    <button
                      type="submit"
                      className="cw-btn cw-btn--primary"
                      style={{ width: "100%" }}
                      disabled={busy || !sponsor}
                    >
                      {busy ? "Registering…" : status === "success" ? "Registered ✓" : "Register"}
                    </button>
                    {error && <p className="cw-err">{error}</p>}
                  </form>
                ) : (
                  /* ---------- Account info (registered) ---------- */
                  <>
                    <MembershipCard
                      balance={fmt(usdtVault)}
                      currency="USDT"
                      badge={rankName}
                      label="Funding Wallet"
                      cardId={addrToCardId(address)}
                      tier={rw?.activated ? RANKS[Number(rw.rank)] : ""}
                    />

                    <div className="cw-actions" style={{ margin: "14px 0 18px" }}>
                      <button
                        type="button"
                        className="cw-btn"
                        style={{ borderRadius: 999, minHeight: 50 }}
                        onClick={() => openSheet("withdraw")}
                      >
                        <i className="la la-arrow-up"></i> Withdraw
                      </button>
                      <button
                        type="button"
                        className="cw-btn cw-btn--primary"
                        style={{ borderRadius: 999, minHeight: 50 }}
                        onClick={() => openSheet("deposit")}
                      >
                        <i className="la la-arrow-down"></i> Deposit
                      </button>
                    </div>

                    {/* Total income rewards — sum of the five earning streams. */}
                    <div className="coc-income-report card-box">
                      <div className="coc-income-total">
                        <span className="cw-total-label">Total Income Rewards</span>
                        <span className="cw-total-value">{fmt(totalIncome)} USDT</span>
                      </div>
                      <div className="coc-income-rows">
                        <div className="coc-income-row">
                          <span>Direct Referral</span>
                          <span>{fmt(directReferralEarned)} USDT</span>
                        </div>
                        <div className="coc-income-row">
                          <span>Override</span>
                          <span>{fmt(overrideEarned)} USDT</span>
                        </div>
                        <div className="coc-income-row">
                          <span>Daily Passive</span>
                          <span>{fmt(dailyPassiveEarned)} USDT</span>
                        </div>
                        <div className="coc-income-row">
                          <span>Direct Passive</span>
                          <span>{fmt(directPassiveEarned)} USDT</span>
                        </div>
                        <div className="coc-income-row">
                          <span>Line Income</span>
                          <span>{fmt(lineIncomeEarned)} USDT</span>
                        </div>
                      </div>
                    </div>

                    <div className="cw-tokens">
                      <div className="cw-eyebrow">Account</div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">Status</span>
                        <span className="cw-token-amt">{active ? "Active" : "Inactive"}</span>
                      </div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">Sponsor</span>
                        <span className="cw-token-amt">
                          {ac && ac.sponsor !== ZERO ? shortAddr(ac.sponsor) : "—"}
                        </span>
                      </div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">Direct referrals</span>
                        <span className="cw-token-amt">{ac ? Number(ac.directCount) : 0}</span>
                      </div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">Income cap left</span>
                        <span className="cw-token-amt">{fmt(rw?.incomeCap)} USDT</span>
                      </div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">USDT → COCT</span>
                        <span className="cw-token-right">
                          <span className="cw-token-amt">{fmt(rw?.tokenBalance)} USDT</span>
                          <ClaimBtn
                            busy={claiming === "claimToken"}
                            disabled={!(rw?.tokenBalance > 0n) || !!claiming}
                            onClick={() => doClaim("claimToken", "product (converted to COCT)")}
                          />
                        </span>
                      </div>
                    </div>

                    <div className="cw-tokens">
                      <div className="cw-eyebrow">Income</div>
                      <p className="cw-modal-sub" style={{ opacity: 0.7, margin: "0 2px 8px" }}>
                        Passive streams accrue over time — Claim to move the pending amount into your Rewards
                        Wallet. Direct Referral &amp; Override are credited to it automatically (no claim).
                      </p>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">Daily passive</span>
                        <span className="cw-token-right">
                          <span className="cw-token-amt">{fmt(rw?.pendingDaily)} USDT</span>
                          <ClaimBtn
                            busy={claiming === "claimDailyPassive"}
                            disabled={!(rw?.pendingDaily > 0n) || !!claiming}
                            onClick={() => doClaim("claimDailyPassive", "daily passive")}
                          />
                        </span>
                      </div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">Direct passive</span>
                        <span className="cw-token-right">
                          <span className="cw-token-amt">{fmt(rw?.pendingDirect)} USDT</span>
                          <ClaimBtn
                            busy={claiming === "claimDirectPassive"}
                            disabled={!(rw?.pendingDirect > 0n) || !!claiming}
                            onClick={() => doClaim("claimDirectPassive", "direct passive")}
                          />
                        </span>
                      </div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">Line income</span>
                        <span className="cw-token-right">
                          <span className="cw-token-amt">{fmt(rw?.pendingLine)} USDT</span>
                          <ClaimBtn
                            busy={claiming === "claimLineIncome"}
                            disabled={!(rw?.pendingLine > 0n) || !!claiming}
                            onClick={() => doClaim("claimLineIncome", "line income")}
                          />
                        </span>
                      </div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">Direct referral</span>
                        <span className="cw-token-right">
                          <span className="cw-token-amt">{fmt(directReferralEarned)} USDT</span>
                          <span className="cw-auto-tag">Auto ✓</span>
                        </span>
                      </div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">Override income</span>
                        <span className="cw-token-right">
                          <span className="cw-token-amt">{fmt(overrideEarned)} USDT</span>
                          <span className="cw-auto-tag">Auto ✓</span>
                        </span>
                      </div>
                      {claimMsg && (
                        <p
                          className="cw-modal-sub"
                          style={{
                            color: claimMsg.type === "error" ? "#e0655f" : "var(--cw-accent)",
                            margin: "4px 2px 0",
                          }}
                        >
                          {claimMsg.text}
                        </p>
                      )}
                    </div>

                    <div className="cw-tokens">
                      <div className="cw-eyebrow">Rewards Wallet</div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">Available</span>
                        <span className="cw-token-right">
                          <span className="cw-token-amt">{fmt(rw?.rewardsBalance)} USDT</span>
                          <button
                            type="button"
                            className="cw-claim"
                            disabled={!(rw?.rewardsBalance > 0n) || !!claiming}
                            onClick={() =>
                              doClaim("withdrawRewards", "rewards to your Funding Wallet (stability fee applied)")
                            }
                          >
                            {claiming === "withdrawRewards" ? "Transferring…" : "Transfer to Funding"}
                          </button>
                        </span>
                      </div>
                      <p className="cw-modal-sub" style={{ opacity: 0.7, margin: "4px 2px 0" }}>
                        Claim the income above to add it to your Rewards Wallet, then transfer it to your Funding
                        Wallet — a rank-based stability fee is deducted. From the Funding
                        Wallet you can withdraw to your external wallet.
                      </p>
                    </div>

                    {agentRewards > 0n && (
                      <div className="cw-tokens">
                        <div className="cw-eyebrow">Agent Rewards</div>
                        <div className="cw-token card-box">
                          <span className="cw-token-sym">Available (to wallet)</span>
                          <span className="cw-token-right">
                            <span className="cw-token-amt">{fmt(agentRewards)} USDT</span>
                            <button
                              type="button"
                              className="cw-claim"
                              disabled={!(agentRewards > 0n) || !!claiming}
                              onClick={() => doClaim("claimAgentRewards", "agent rewards to your wallet")}
                            >
                              {claiming === "claimAgentRewards" ? "Claiming…" : "Claim to wallet"}
                            </button>
                          </span>
                        </div>
                        <p className="cw-modal-sub" style={{ opacity: 0.7, margin: "4px 2px 0" }}>
                          Network-leader incentive (uncapped). Claiming sends USDT straight to your connected
                          wallet.
                        </p>
                      </div>
                    )}

                    <div className="cw-tokens">
                      <div className="cw-eyebrow">Funding Wallet</div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">USDT</span>
                        <span className="cw-token-amt">{fmt(usdtVault)}</span>
                      </div>
                      <div className="cw-token card-box">
                        <span className="cw-token-sym">COCT</span>
                        <span className="cw-token-amt">{fmt(coctVault)}</span>
                      </div>
                    </div>
                  </>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Deposit / Withdraw modal — full-cover, interacts with COCTAssets. */}
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
            <span className="cw-modal-title">
              {sheet === "deposit" ? "Deposit USDT" : "Withdraw USDT"}
            </span>
          </div>
          <div className="cw-modal-body">
            <p className="cw-modal-sub">
              Funding Wallet: {fmt(usdtVault)} USDT · External wallet: {fmt(walletUsdt)} USDT
            </p>

            {sheet === "deposit" ? (
              <>
                <div className="cw-field">
                  <div
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      alignItems: "baseline",
                    }}
                  >
                    <label style={{ paddingBottom: 0 }}>Amount (USDT) — min {MIN_DEPOSIT}</label>
                    <button
                      type="button"
                      onClick={() => setDepAmt(formatUnits(walletUsdt, 18))}
                      disabled={txBusy || walletUsdt === 0n}
                      title="Deposit your full wallet balance"
                      style={{
                        background: "none",
                        border: "none",
                        padding: 0,
                        minHeight: 0,
                        color: "var(--cw-accent)",
                        fontSize: 12,
                        fontWeight: 700,
                        cursor: walletUsdt === 0n ? "not-allowed" : "pointer",
                      }}
                    >
                      MAX {fmt(walletUsdt)}
                    </button>
                  </div>
                  <input
                    value={depAmt}
                    onChange={(e) => setDepAmt(e.target.value)}
                    placeholder={`e.g. ${MIN_DEPOSIT}`}
                    inputMode="decimal"
                    disabled={txBusy}
                  />
                </div>
                {depError && (
                  <p className="cw-modal-sub" style={{ color: "#e0655f", marginBottom: 12 }}>
                    {depError}
                  </p>
                )}
                <button
                  type="button"
                  className="cw-btn cw-btn--primary"
                  onClick={doDeposit}
                  disabled={txBusy || !depOk}
                >
                  {txBusy ? "Depositing…" : "Deposit to Funding Wallet"}
                </button>
              </>
            ) : (
              <>
                <p className="cw-modal-sub">
                  Pick a denomination — no vault fee; a 24h cooldown applies (COCTAssets):
                </p>
                <div className="cw-actions" style={{ flexWrap: "wrap" }}>
                  {[20, 50, 100].map((d) => (
                    <button
                      key={d}
                      type="button"
                      className="cw-btn cw-btn--primary"
                      onClick={() => doWithdraw(d)}
                      disabled={txBusy || usdtVault < parseUnits(String(d), 18)}
                    >
                      ${d}
                    </button>
                  ))}
                </div>
              </>
            )}

            {txMsg && (
              <p
                className={txMsg.type === "error" ? "cw-err" : ""}
                style={{
                  marginTop: 12,
                  color: txMsg.type === "success" ? "var(--cw-accent)" : undefined,
                }}
              >
                {txMsg.text}
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// Small inline claim pill for a claimable income row. Disabled when there's nothing to claim
// or another claim is already in flight.
function ClaimBtn({ onClick, disabled, busy }) {
  return (
    <button
      type="button"
      className="cw-claim"
      onClick={onClick}
      disabled={disabled}
    >
      {busy ? "Claiming…" : "Claim"}
    </button>
  );
}
