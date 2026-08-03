import { useState } from "react";
import { useTheme } from "../theme/ThemeContext.jsx";
import { themeColors } from "../data/site.js";

const BG_DEMOS = [
  { key: "image", label: "BG Image" },
  { key: "video", label: "BG Video" },
  { key: "particles", label: "BG Particles" },
  { key: "color", label: "BG Color" },
];

export default function SettingsPanel() {
  const { color, setColor, rtl, setRtl, bg, setBg } = useTheme();
  const [open, setOpen] = useState(true);

  return (
    <div className={`theme_panel${open ? " active" : ""}`}>
      <div className="theme_menu">
        <a
          href="https://t.me/"
          target="_blank"
          rel="noreferrer"
          className="buy-btn"
        >
          {/* the vendored Line Awesome font has no telegram glyph — inline mark */}
          <svg className="icon" viewBox="0 0 24 24" aria-hidden="true">
            <path
              fill="currentColor"
              d="M9.78 18.65l.28-4.23 7.68-6.92c.34-.31-.07-.46-.52-.19L7.74 13.3 3.64 12c-.88-.25-.89-.86.2-1.3l15.97-6.16c.73-.33 1.43.18 1.15 1.3l-2.72 12.81c-.19.91-.74 1.13-1.5.71L12.6 16.3l-1.99 1.93c-.23.23-.42.42-.83.42z"
            />
          </svg>
          Contact Me
        </a>

        <h4>Color Switcher</h4>
        <div className="segment">
          <ul className="theme layout_style">
            {themeColors.map((c) => (
              <li key={c.id}>
                <a
                  title={`theme-${c.id}`}
                  href="#change_background_style"
                  data-color={c.id}
                  aria-current={color === c.id}
                  style={{ backgroundColor: c.hex }}
                  onClick={(e) => { e.preventDefault(); setColor(c.id); }}
                >
                  &nbsp;
                </a>
              </li>
            ))}
          </ul>
        </div>
        <div className="clear"></div>

        <h4>RTL/LTR Version</h4>
        <ul className="theme demo_list">
          <li style={{ width: "50%" }}>
            <a href="#rtl" onClick={(e) => { e.preventDefault(); setRtl(true); }}>
              <strong>RTL</strong>
            </a>
          </li>
          <li style={{ width: "50%" }}>
            <a href="#ltr" onClick={(e) => { e.preventDefault(); setRtl(false); }}>
              <strong>ltr</strong>
            </a>
          </li>
        </ul>
        <div className="clear"></div>

        <h4>Background Demos</h4>
        <ul className="theme demo_list">
          {BG_DEMOS.map((d) => (
            <li key={d.key} style={{ width: "50%" }}>
              <a
                href={`#${d.key}`}
                style={{ cursor: "pointer", opacity: bg === d.key ? 1 : 0.7 }}
                onClick={(e) => { e.preventDefault(); setBg(d.key); }}
              >
                <strong>{d.label}</strong>
              </a>
            </li>
          ))}
        </ul>
        <div className="clear"></div>
      </div>

      <div className="toggle_bts">
        <a
          className="toggle-theme-panel"
          href="#theme_panel"
          onClick={(e) => { e.preventDefault(); setOpen((o) => !o); }}
        >
          <i className="icon la la-gear"></i>
        </a>
      </div>
    </div>
  );
}
