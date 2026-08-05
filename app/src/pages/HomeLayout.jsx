import { useState } from "react";
import { Tabs, TabList, Tab, TabPanel } from "react-tabs";
import { site } from "../data/site.js";
import SettingsPanel from "../components/SettingsPanel.jsx";
import Home from "../sections/Home.jsx";
import About from "../sections/About.jsx";
import Subscribe from "../sections/Subscribe.jsx";
import Portfolio from "../sections/Portfolio.jsx";
import BlogTab from "../sections/BlogTab.jsx";
import Wallet from "../sections/Wallet.jsx";
import Tree from "../sections/Tree.jsx";

// Order matches site.nav — panel N pairs with tab N.
const PANELS = [Home, About, Subscribe, Portfolio, BlogTab, Wallet, Tree];

export default function HomeLayout() {
  // Mobile nav open/close — original adds `.opened` to the header on burger tap.
  const [menuOpen, setMenuOpen] = useState(true); // open by default; stays open until the user taps the X

  return (
    <div className="page">
      <Tabs>
        {/* The header IS the react-tabs TabList (deep-nested Tabs, like the original) */}
        <TabList className={`header${menuOpen ? " opened" : ""}`}>
          <div className="logo">
            <a href="/">
              {site.logo ? (
                <img className="brand-logo" src={site.logo} alt={`${site.name.first}${site.name.last}`} />
              ) : (
                <span>{site.brand}</span>
              )}
            </a>
          </div>

          <div className="top-menu">
            <ul>
              {site.nav.map((n) => (
                <Tab key={n.id}>
                  <a href={`#${n.id}`}>
                    <span className={`icon ${n.icon}`}></span>
                    <span className="link">{n.label}</span>
                  </a>
                </Tab>
              ))}
            </ul>
          </div>

          <div className="social" hidden>
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
        </TabList>
        <SettingsPanel />
        <div className="container">
          {PANELS.map((Panel, i) => (
            <TabPanel key={i}>
              <Panel />
            </TabPanel>
          ))}
        </div>
      </Tabs>
    </div>
  );
}
