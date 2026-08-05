import StaticHeader from "../components/StaticHeader.jsx";
import Account from "../sections/Account.jsx";

export default function AccountsPage() {
  return (
    <div className="page">
      <StaticHeader />
      <div className="container">
        <Account />
      </div>
    </div>
  );
}
