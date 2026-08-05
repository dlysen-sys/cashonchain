import { useTheme } from "../theme/ThemeContext.jsx";
import { site } from "../data/site.js";
import HeroBackground from "../components/HeroBackground.jsx";
import Typed from "../components/Typed.jsx";

export default function Home() {
  const { bg } = useTheme();
  return (
    <div className="card-inner card-started active" id="home-card" style={{ height: "100vh" }}>
      <HeroBackground mode={bg} />
      <div className="centrize full-width">
        <div className="vertical-center">
          {site.logo && (
            <img
              className="coc-hero-logo"
              src={site.logo}
              alt={`${site.name.first}${site.name.last}`}
            />
          )}
          <div className="title">
            <span>{site.name.first}</span>{site.name.last}
          </div>
          <div
            className="subtitle"
            style={{ display: "flex", gap: 10, justifyContent: "center", alignItems: "center" }}
          >
            COC!
            <Typed words={site.roles} />
          </div>
        </div>
      </div>
    </div>
  );
}
