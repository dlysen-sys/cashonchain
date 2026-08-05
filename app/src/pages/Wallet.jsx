import StaticHeader from "../components/StaticHeader.jsx";
import Wallet from "../sections/Wallet.jsx";
export default function WalletPage() {
  return (
    <div className="page">
      <StaticHeader />
      <div className="container">
          {Wallet && <Wallet />}
      </div>
    </div>
  );
}
