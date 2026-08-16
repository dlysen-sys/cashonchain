import { useState } from "react";

// Purchase contact — the Buy button opens a prefilled email; the address is also shown as text.
const CONTACT_EMAIL = "contact@cashonchain.network";

const money = (n) => `${n.toLocaleString("en-US")} USDT`;

// Product catalog. `image` (optional) overrides the emoji hero when a real photo is dropped in /public.
const PRODUCTS = [
  {
    id: "trading-bot",
    name: "Ultimate Trading Bot",
    price: 20000,
    emoji: "🤖",
    image: "/images/ultimate-trading-bot-node.png",
    gradient: "linear-gradient(135deg,#0f3d2e 0%,#12b886 55%,#0f3d2e 100%)",
    short:
      "An AI bot that runs deep technical analysis, backtests every strategy, and learns market patterns and behavior — trading with a high win rate and consistently excellent results.",
    headline: "Trade Like the Top 1% — On Autopilot.",
    sub: "The Ultimate Trading Bot reads the market, proves every strategy against history, and executes with machine precision — 24/7, without fear, greed, or hesitation.",
    body:
      "Most traders lose because they trade on emotion and act too late. The Ultimate Trading Bot removes both. It scans the market continuously, runs institutional-grade technical analysis, and only takes a position after the setup has been backtested against years of real data. Then it executes instantly — protecting your capital with disciplined risk controls on every single trade.",
    bullets: [
      "Institutional-grade technical analysis across dozens of indicators, in real time.",
      "Every strategy backtested on years of historical data before a live trade is placed.",
      "Self-learning engine that adapts to shifting market patterns and trader behavior.",
      "Consistently high win rate with cold, emotion-free execution.",
      "Trades 24/7 — never miss a setup, never fall for FOMO or fear.",
      "Built-in risk management: position sizing, stop-loss, and drawdown guards.",
    ],
    close: "Stop guessing. Start compounding.",
  },
  {
    id: "tg-signal",
    name: "Telegram Signal — Bitcoin Market Price Forecast",
    price: 10000,
    emoji: "📡",
    image: "/images/ultimate-trading-bot-telegram.png",
    gradient: "linear-gradient(135deg,#12233f 0%,#4c8dff 55%,#6a3df0 100%)",
    short:
      "Premium crypto signals delivered straight to your phone — timely Bitcoin and altcoin price forecasts with clear entries, targets, and exits.",
    headline: "Premium Crypto Signals, Straight to Your Phone.",
    sub: "Bitcoin and altcoin forecasts from a proven market model — actionable entries, take-profit targets, and stop-losses, delivered in real time on Telegram.",
    body:
      "The move happens whether you're watching the charts or not. Our premium Telegram channel makes sure you're never a step behind — every high-conviction call is pushed to your phone the moment it matters, with the exact levels you need to act. No noise, no hype, no guesswork: just clear, data-driven forecasts you can trade with confidence.",
    bullets: [
      "Daily high-conviction signals for Bitcoin and top altcoins.",
      "Clear entries, take-profit targets, and stop-losses — never trade blind.",
      "Market-price forecasts powered by data and market structure, not hype.",
      "Instant Telegram alerts so you act before the move, not after it.",
      "Trend, momentum, and sentiment distilled into simple, actionable calls.",
      "Private members-only channel with priority support.",
    ],
    close: "Never trade blind again.",
  },
];

function buyHref(p) {
  const subject = `Purchase: ${p.name} (${money(p.price)})`;
  const body = `Hi, I'd like to purchase "${p.name}" for ${money(
    p.price
  )}.\n\nPlease send the payment details and setup instructions.\n\nThank you.`;
  return `mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

function Hero({ product, tall }) {
  return (
    <div
      className={`coc-mkt-hero${tall ? " coc-mkt-hero--tall" : ""}`}
      style={{ background: product.gradient }}
    >
      {product.image ? (
        <img src={product.image} alt={product.name} />
      ) : (
        <span className="coc-mkt-hero-emoji" aria-hidden="true">
          {product.emoji}
        </span>
      )}
    </div>
  );
}

export default function Market() {
  const [active, setActive] = useState(null); // selected product for the drawer

  return (
    <div className="card-inner active coc-wallet-card" id="market-card">
      <div className="row card-container">
        <div className="card-wrap col col-m-12 col-t-12 col-d-8 col-d-lg-6" data-simplebar="true">
          <div
            className="card-image col col-m-12 col-t-12 col-d-4 col-d-lg-6"
            style={{ backgroundImage: 'url("/static/media/profile2.8c37e2bf24adf94ad8cc.jpg")' }}
          ></div>

          <div className="content inner-top">
            <div className="row">
              <div className="col col-m-12 col-t-12 col-d-12 col-d-lg-12">
                <div className="title-bg">Market</div>
              </div>
            </div>
          </div>

          <div className="content coc-wallet">
            <div className="row">
              <div className="col col-m-12 col-t-12 col-d-12 col-d-lg-12">
                <div className="title">
                  <span>Product</span> Catalog
                </div>

                <div className="cw-eyebrow">Available now</div>
                <div className="coc-mkt-grid">
                  {PRODUCTS.map((p) => (
                    <button
                      key={p.id}
                      type="button"
                      className="coc-mkt-card card-box"
                      onClick={() => setActive(p)}
                    >
                      <Hero product={p} />
                      <div className="coc-mkt-card-body">
                        <div className="coc-mkt-name">{p.name}</div>
                        <p className="coc-mkt-short">{p.short}</p>
                        <div className="coc-mkt-row">
                          <span className="coc-mkt-price">{money(p.price)}</span>
                          <span className="coc-mkt-view">
                            View details <i className="la la-arrow-right"></i>
                          </span>
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Product drawer — photo → sales copy → buy → email. */}
      {active && (
        <div className="cw-modal coc-wallet" role="dialog" aria-modal="true">
          <div className="cw-modal-head">
            <button
              type="button"
              className="cw-modal-close"
              onClick={() => setActive(null)}
              aria-label="Back"
            >
              <i className="la la-arrow-left"></i>
            </button>
            <span className="cw-modal-title">{active.name}</span>
          </div>

          <div className="cw-modal-body">
            {/* 1) product photo */}
            <Hero product={active} tall />

            {/* 2) sales copy */}
            <div className="coc-mkt-sale">
              <h2 className="coc-mkt-headline">{active.headline}</h2>
              <p className="coc-mkt-sub">{active.sub}</p>
              <p className="coc-mkt-body">{active.body}</p>
              <ul className="coc-mkt-bullets">
                {active.bullets.map((b, i) => (
                  <li key={i}>
                    <i className="la la-check"></i>
                    <span>{b}</span>
                  </li>
                ))}
              </ul>
              <p className="coc-mkt-close">{active.close}</p>

              <div className="coc-mkt-pricebar">
                <span className="coc-mkt-pricebar-label">One-time price</span>
                <span className="coc-mkt-pricebar-value">{money(active.price)}</span>
              </div>
            </div>

            {/* 3) buy button */}
            <a href={buyHref(active)} className="cw-btn cw-btn--primary" style={{ width: "100%" }}>
              <i className="la la-shopping-cart"></i> Buy now — {money(active.price)}
            </a>

            {/* 4) email address */}
            <p className="coc-mkt-contact">
              Prefer to talk first? Email{" "}
              <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
