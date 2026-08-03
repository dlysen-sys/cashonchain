import StaticHeader from "../components/StaticHeader.jsx";
import SettingsPanel from "../components/SettingsPanel.jsx";
import Dashboard from "../sections/Dashboard.jsx";
export default function DashboardPage() {
  return (
    <div className="page">
      <StaticHeader />
      <SettingsPanel />
      <div className="container">
          {Dashboard && <Dashboard />}
      </div>
    </div>
  );
}