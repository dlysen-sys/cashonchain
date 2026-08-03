import StaticHeader from "../components/StaticHeader.jsx";
import SettingsPanel from "../components/SettingsPanel.jsx";
import raw from "../sections/blog-route.html?raw";

export default function Blog() {
  return (
    <div className="page">
      <StaticHeader />
      <SettingsPanel />
      <div className="container" dangerouslySetInnerHTML={{ __html: raw }} />
    </div>
  );
}
