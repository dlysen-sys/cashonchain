import raw from "./portfolio.html?raw";
// Faithful section markup (editable HTML). Structural/interactive chrome
// lives in real components; static body content stays as HTML here.
export default function Portfolio() {
  return <div dangerouslySetInnerHTML={{ __html: raw }} />;
}
