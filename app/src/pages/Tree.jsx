import StaticHeader from "../components/StaticHeader.jsx";
import SettingsPanel from "../components/SettingsPanel.jsx";
import Tree from "../sections/Tree.jsx";

export default function TreePage() {
  return (
    <div className="page">
      <StaticHeader />
      <SettingsPanel />
      <div className="container">
        <Tree />
      </div>
    </div>
  );
}
