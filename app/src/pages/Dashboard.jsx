import StaticHeader from "../components/StaticHeader.jsx";
import Dashboard from "../sections/Dashboard.jsx";
export default function DashboardPage() {
  return (
    <div className="page">
      <StaticHeader /> 
      <div className="container">
          {Dashboard && <Dashboard />}
      </div>
    </div>
  );
}