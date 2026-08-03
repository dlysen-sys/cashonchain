import StaticHeader from "../components/StaticHeader.jsx";
import SettingsPanel from "../components/SettingsPanel.jsx";
import Account from "../sections/Account.jsx";

export default function AccountsPage() {
  return (
    <div className="page">
      <StaticHeader />
      <SettingsPanel />
      <div className="container">
        <Account />
      </div>
    </div>
  );
}
