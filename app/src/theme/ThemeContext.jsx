import { createContext, useContext, useEffect, useState } from "react";
import { DEFAULT_COLOR } from "../data/site.js";

const ThemeContext = createContext(null);
export const useTheme = () => useContext(ThemeContext);

const RTL_ID = "rtl-stylesheet";

export function ThemeProvider({ children }) {
  const [color, setColor] = useState(DEFAULT_COLOR);
  const [rtl, setRtl] = useState(false);
  // background variant: "image" | "video" | "particles" | "color"
  const [bg, setBg] = useState("particles");

  // Swap the accent-color stylesheet (mirrors the original link-swapping trick).
  useEffect(() => {
    let link = document.getElementById("theme-color-link");
    if (!link) {
      link = document.createElement("link");
      link.id = "theme-color-link";
      link.rel = "stylesheet";
      document.head.appendChild(link);
    }
    link.href = `/css/theme-colors/${color}.css`;
  }, [color]);

  // Inject / remove rtl.css and flip the document direction.
  useEffect(() => {
    const existing = document.getElementById(RTL_ID);
    if (rtl && !existing) {
      const l = document.createElement("link");
      l.id = RTL_ID;
      l.rel = "stylesheet";
      l.href = "/css/rtl.css";
      document.head.appendChild(l);
    } else if (!rtl && existing) {
      existing.remove();
    }
    document.documentElement.dir = rtl ? "rtl" : "ltr";
  }, [rtl]);

  const value = { color, setColor, rtl, setRtl, bg, setBg };
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}
