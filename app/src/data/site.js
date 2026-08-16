// ─────────────────────────────────────────────────────────────
// EDIT ME — top-level content config for the site.
// Section bodies (About/Resume/Portfolio/Blog/Contact) live as
// editable HTML in src/sections/*.html.
// ─────────────────────────────────────────────────────────────

export const site = {
  brand: "C", // fallback text mark (used only if `logo` is unset)
  logo: "/logo512.png", // brand emblem (512px, ~317KB) — header badge + floating hero. Source: /logo.png
  name: { first: "Cash", last: "onChain" },

  // Words cycled by the typing effect in the hero.
  roles: [
    "Concentrated community effort.",
    "Oneline opportunity income stream.",
    "Unlimted income potential.",
    "Global decentralized network.",
  ],

  // Left sidebar navigation (tab id must match a section key below).
  nav: [
    { id: "home", label: "Home", icon: "la la-home" },
    { id: "account", label: "Account", icon: "la la-user" },
    { id: "subscribe", label: "subscribe", icon: "la la-bell" },
    { id: "tree", label: "tree", icon: "la la-sitemap" },
    { id: "wallet", label: "wallet", icon: "la la-credit-card" },
    { id: "market", label: "Market", icon: "la la-store", svg: "store" },
  ],

  // Only verified profiles are listed. Add LinkedIn / X / Telegram here
  // once the handles are confirmed — e.g.
  //   { icon: "la la-linkedin", href: "https://linkedin.com/in/<handle>" },
  social: [
    { icon: "la la-github", href: "https://github.com/" },
    { icon: "la la-envelope", href: "mailto:contact@cashonchain.network" },
  ],

  heroBg: "/static/media/bg.3caafa4fb88fc8aa6fc5.jpg",
  heroVideo: "/static/media/intro_1.f80b512b05c37300cbfa.mp4",
};

// Accent colors used by the settings panel (file → /css/theme-colors/<id>.css).
export const themeColors = [
  { id: "green", hex: "#5ac24e" },
  { id: "blue", hex: "#65b4f3" },
  { id: "orange", hex: "#f5a640" },
  { id: "pink", hex: "#ee6192" },
  { id: "purple", hex: "#bb68c8" },
  { id: "red", hex: "#ee534f" },
];

export const DEFAULT_COLOR = "green";
