import { useState } from "react";
import { Link, useLocation } from "react-router-dom";
import { site } from "../data/site.js";

// Non-tab header for standalone routes (blog, wallet, …). Each nav id maps to a route (/${id});
// the item matching the current URL gets the active/selected classes so its icon takes the accent.
export default function StaticHeader() {
  const [menuOpen, setMenuOpen] = useState(false);
  const { pathname } = useLocation();
  return (
    <ul className={`header${menuOpen ? " opened" : ""}`}>
      <div className="logo">
        <Link to="/home"><span>{site.brand}</span></Link>
      </div>
      <div className="top-menu">
        <ul>
          {site.nav.map((n) => {
            const active = pathname === `/${n.id}`;
            return (
              <li
                key={n.id}
                className={`react-tabs__tab${active ? " active react-tabs__tab--selected" : ""}`}
              >
                <Link to={`/${n.id}`}>
                  <span className={`icon ${n.icon}`}></span>
                  <span className="link">{n.label}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      </div>
      <div className="social">
        {site.social.map((s, i) => (
          <a key={i} target="_blank" rel="noreferrer" href={s.href}>
            <span className={`icon ${s.icon}`}></span>
          </a>
        ))}
      </div>
      <span
        className="menu-btn"
        onClick={() => setMenuOpen((o) => !o)}
        role="button"
        aria-label="Toggle menu"
        aria-expanded={menuOpen}
      >
        <span className="m-line"></span>
      </span>
    </ul>
  );
}
