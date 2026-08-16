import StaticHeader from "../components/StaticHeader.jsx";
import Market from "../sections/Market.jsx";

export default function MarketPage() {
  return (
    <div className="page">
      <StaticHeader />
      <div className="container">
        <Market />
      </div>
    </div>
  );
}
