import { useMemo, useState } from "react";

// ── COC income-projection calculator (client-side forecast, no chain reads) ──
// Model: every member sponsors N directs, so level L holds N^L members (the
// "directs to the power of the level" growth the owner asked for). Each member
// activates the SAME package once. We project the rewards that flow up to YOU
// (the root) across every COC stream, then summarize total network + total
// income. Figures are a gross projection — see the 200%-cap note in the UI.
const TIERS = [
  { name: "Silver", entry: 20, overridePct: 0 },
  { name: "Gold", entry: 50, overridePct: 1 },
  { name: "Platinum", entry: 100, overridePct: 2 },
  { name: "Diamond", entry: 500, overridePct: 3 },
  { name: "Emerald", entry: 1000, overridePct: 4 },
  { name: "Black Diamond", entry: 5000, overridePct: 5 },
];

const LINE_LEVELS = 10; // line income walks up to 10 uplines
const MAX_LEVELS = 12; // keep N^L inside JS safe-integer range for the forecast

// Compact money/'count' formatter: 1,250 · 3.4K · 12.7M · 1.9B · 4.2T.
function abbr(n) {
  if (!isFinite(n)) return "∞";
  const units = [
    ["T", 1e12],
    ["B", 1e9],
    ["M", 1e6],
    ["K", 1e3],
  ];
  for (const [s, v] of units) {
    if (Math.abs(n) >= v) return (n / v).toFixed(2).replace(/\.?0+$/, "") + s;
  }
  // Below 1K: keep integers clean ($3, $40) but preserve sub-dollar values ($0.20).
  return (Number.isInteger(n) ? n : Number(n.toFixed(2))).toLocaleString();
}

export default function IncomeCalculator() {
  const [directs, setDirects] = useState("3");
  const [levels, setLevels] = useState("5");
  const [tierIdx, setTierIdx] = useState(0);

  const model = useMemo(() => {
    const N = Math.max(0, Math.floor(Number(directs) || 0));
    const D = Math.min(MAX_LEVELS, Math.max(0, Math.floor(Number(levels) || 0)));
    const tier = TIERS[tierIdx];
    const E = tier.entry;

    // Members at each level L = N^L (L = 1..D).
    const perLevel = [];
    for (let L = 1; L <= D; L++) perLevel.push(Math.pow(N, L));
    const totalNetwork = perLevel.reduce((a, b) => a + b, 0);
    const withinLine = perLevel
      .slice(0, Math.min(D, LINE_LEVELS))
      .reduce((a, b) => a + b, 0);
    const directsCount = perLevel[0] || 0; // level-1 members

    // ── Streams that flow up to YOU ──
    // From your own package (personal):
    const dailyPassive = 2 * E; // own entry, 1%/day, 200% max
    const productToken = 0.01 * E; // 1% product token value

    // From your network (downline activations):
    const directReferral = 0.05 * E * directsCount; // 5% of each direct's entry (L1)
    const directPassive = 1.0 * E * directsCount; // 50% mirror → 2× cap = 1×E each (L1)
    const lineIncome = 0.2 * E * withinLine; // 10%/lvl ×10 levels → 2× cap = 0.2×E each
    const override = (tier.overridePct / 100) * E * totalNetwork; // rank-diff (top-rank assumption)

    const networkIncome = directReferral + directPassive + lineIncome + override;
    const personalIncome = dailyPassive + productToken;
    const totalIncome = networkIncome + personalIncome;

    return {
      N,
      D,
      tier,
      E,
      totalNetwork,
      directsCount,
      rows: [
        { key: "dr", label: "Direct Referral (5%)", value: directReferral, group: "network" },
        { key: "dp", label: "Direct Passive (50% → 200%)", value: directPassive, group: "network" },
        { key: "li", label: `Line Income (10% × ${LINE_LEVELS} levels)`, value: lineIncome, group: "network" },
        { key: "ov", label: `Override (${tier.overridePct}% rank differential)`, value: override, group: "network" },
        { key: "daily", label: "Daily Passive (your package → 200%)", value: dailyPassive, group: "personal" },
        { key: "prod", label: "Product Token (1%)", value: productToken, group: "personal" },
      ],
      networkIncome,
      personalIncome,
      totalIncome,
      cap: 2 * E,
    };
  }, [directs, levels, tierIdx]);

  return (
    <div className="card-box coc-calc">
      <div className="cw-eyebrow">Income Calculator — projection</div>
      <p className="coc-calc__intro">
        Assume every member sponsors the same number of directs. Each level multiplies
        by that number (directs<sup>level</sup>). We forecast the rewards flowing up to you.
      </p>

      <div className="coc-calc__inputs">
        <div className="cw-field">
          <label>Directs (per member)</label>
          <input
            type="number"
            min="1"
            max="50"
            inputMode="numeric"
            value={directs}
            onChange={(e) => setDirects(e.target.value)}
          />
        </div>
        <div className="cw-field">
          <label>Levels deep (max {MAX_LEVELS})</label>
          <input
            type="number"
            min="1"
            max={MAX_LEVELS}
            inputMode="numeric"
            value={levels}
            onChange={(e) => setLevels(e.target.value)}
          />
        </div>
        <div className="cw-field">
          <label>Package</label>
          <select value={tierIdx} onChange={(e) => setTierIdx(Number(e.target.value))}>
            {TIERS.map((t, i) => (
              <option key={t.name} value={i}>
                {t.name} — ${t.entry.toLocaleString()}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="coc-calc__summary">
        <div className="coc-calc__stat">
          <div className="cw-total-label">Total network</div>
          <div className="cw-total-value">{abbr(model.totalNetwork)}</div>
          <small>members across {model.D} levels</small>
        </div>
        <div className="coc-calc__stat">
          <div className="cw-total-label">Total income projected</div>
          <div className="cw-total-value">${abbr(model.totalIncome)}</div>
          <small>gross · all streams · USDT</small>
        </div>
      </div>

      <div className="coc-calc__breakdown">
        <div className="coc-calc__grouphead">From your network</div>
        {model.rows
          .filter((r) => r.group === "network")
          .map((r) => (
            <div className="coc-calc__row" key={r.key}>
              <span>{r.label}</span>
              <strong>${abbr(r.value)}</strong>
            </div>
          ))}
        <div className="coc-calc__grouphead">From your package</div>
        {model.rows
          .filter((r) => r.group === "personal")
          .map((r) => (
            <div className="coc-calc__row" key={r.key}>
              <span>{r.label}</span>
              <strong>${abbr(r.value)}</strong>
            </div>
          ))}
      </div>

      <p className="coc-calc__note">
        Projection only — actual results depend on real network growth and activity. Each
        activation is capped at <b>200% of your package (${model.cap.toLocaleString()})</b>;
        figures show cumulative potential as you re-cycle and rank up.
      </p>
    </div>
  );
}
