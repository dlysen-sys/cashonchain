import StaticHeader from "../components/StaticHeader.jsx";
import Subscribe from "../sections/Subscribe.jsx";
export default function SubscribePage() {
  return (
    <div className="page">
      <StaticHeader />
      <div className="container">
        {Subscribe && <Subscribe />}
      </div>
    </div>
  );
}
