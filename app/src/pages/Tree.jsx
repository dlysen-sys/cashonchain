import StaticHeader from "../components/StaticHeader.jsx";
import Tree from "../sections/Tree.jsx";

export default function TreePage() {
  return (
    <div className="page">
      <StaticHeader />
      <div className="container">
        <Tree />
      </div>
    </div>
  );
}
