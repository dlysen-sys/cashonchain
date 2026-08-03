export const usd = (n) =>
  (n ?? 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

// Trim trailing zeros; show more precision for small balances.
export const amt = (n) => {
  if (!n) return "0";
  const d = n < 1 ? 6 : 4;
  return parseFloat(n.toFixed(d)).toString();
};

export const shortAddr = (a) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "");
