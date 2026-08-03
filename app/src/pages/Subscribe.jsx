import StaticHeader from "../components/StaticHeader.jsx";
import SettingsPanel from "../components/SettingsPanel.jsx";
import Subscribe from "../sections/Subscribe.jsx";
export default function SubscribePage() {
  return (
    <div className="page">
      <StaticHeader />
      <SettingsPanel />
      <div className="container">
        {Subscribe && <Subscribe />}
      </div>
    </div>
  );
}
