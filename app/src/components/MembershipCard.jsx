// Reusable floating "visa-style" card (adapted from orbix's MembershipCard) — themed for COC.
// Styles live in overrides.css (.coc-memcard*). Use it anywhere a balance/rank badge looks good.
export default function MembershipCard({
  balance = "0.00",
  currency = "USDT",
  badge = "Member",
  label = "Available Balance",
  cardId = "•••• •••• •••• 0000",
  footer = "Cash On Chain",
  brand = "COCT",
}) {
  return (
    <div className="coc-memcard">
      <div className="coc-memcard__shine" />
      <div className="coc-memcard__top">
        <span className="coc-memcard__brand">
          <span className="coc-memcard__logo">C</span>
          {brand}
        </span>
        <span className="coc-memcard__badge">{badge}</span>
      </div>
      <div className="coc-memcard__chip" />
      <div className="coc-memcard__label">{label}</div>
      <div className="coc-memcard__balance">
        {balance}
        <span>{currency}</span>
      </div>
      <div className="coc-memcard__foot">
        <span className="coc-memcard__id">{cardId}</span>
        <span>{footer}</span>
      </div>
    </div>
  );
}

// Format an address as a masked card number: •••• •••• •••• <last4>
export function addrToCardId(address) {
  if (!address) return "•••• •••• •••• 0000";
  return `•••• •••• •••• ${address.slice(-4).toUpperCase()}`;
}
