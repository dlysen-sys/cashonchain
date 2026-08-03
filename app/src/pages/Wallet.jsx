import StaticHeader from "../components/StaticHeader.jsx";
import SettingsPanel from "../components/SettingsPanel.jsx";
import Wallet from "../sections/Wallet.jsx";
export default function WalletPage() {
  return (
    <div className="page">
      <StaticHeader />
      <SettingsPanel />
      <div className="container">
          {Wallet && <Wallet />}
      </div>
    </div>
  );
}
