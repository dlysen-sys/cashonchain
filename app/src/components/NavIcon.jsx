// Renders a nav item's icon. Most items use the vendored Line Awesome font (`item.icon`),
// but some glyphs (e.g. a storefront-with-awning) aren't in that FA4-era font, so an item can
// set `item.svg` to render a guaranteed inline SVG instead. SVGs use currentColor, so the
// theme's active/hover accent recolors them just like the font icons.

const SVGS = {
  // Lucide "store" (MIT) — storefront with a scalloped canopy/awning.
  store: (
    <svg
      viewBox="0 0 24 24"
      width="21"
      height="21"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="m2 7 4.41-4.41A2 2 0 0 1 7.83 2h8.34a2 2 0 0 1 1.42.59L22 7" />
      <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8" />
      <path d="M15 22v-4a2 2 0 0 0-2-2h-2a2 2 0 0 0-2 2v4" />
      <path d="M2 7h20" />
      <path d="M22 7v3a2 2 0 0 1-2 2 2.7 2.7 0 0 1-1.59-.63.7.7 0 0 0-.82 0A2.7 2.7 0 0 1 16 12a2.7 2.7 0 0 1-1.59-.63.7.7 0 0 0-.82 0A2.7 2.7 0 0 1 12 12a2.7 2.7 0 0 1-1.59-.63.7.7 0 0 0-.82 0A2.7 2.7 0 0 1 8 12a2.7 2.7 0 0 1-1.59-.63.7.7 0 0 0-.82 0A2.7 2.7 0 0 1 4 12a2 2 0 0 1-2-2V7" />
    </svg>
  ),
};

export default function NavIcon({ item }) {
  if (item.svg && SVGS[item.svg]) {
    return <span className="icon coc-nav-svg">{SVGS[item.svg]}</span>;
  }
  return <span className={`icon ${item.icon}`}></span>;
}
