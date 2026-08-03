import { useEffect, useRef } from "react";
import { site } from "../data/site.js";

// Lightweight canvas particle field — replaces the original particles lib.
function Particles() {
  const ref = useRef(null);
  useEffect(() => {
    const canvas = ref.current;
    const ctx = canvas.getContext("2d");
    let raf, w, h;
    const N = 70;
    const pts = [];
    const resize = () => { w = canvas.width = canvas.offsetWidth; h = canvas.height = canvas.offsetHeight; };
    resize();
    window.addEventListener("resize", resize);
    for (let i = 0; i < N; i++)
      pts.push({ x: Math.random() * w, y: Math.random() * h, vx: (Math.random() - 0.5) * 0.4, vy: (Math.random() - 0.5) * 0.4 });
    const step = () => {
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = "rgba(255,255,255,0.7)";
      for (const p of pts) {
        p.x += p.vx; p.y += p.vy;
        if (p.x < 0 || p.x > w) p.vx *= -1;
        if (p.y < 0 || p.y > h) p.vy *= -1;
        ctx.beginPath(); ctx.arc(p.x, p.y, 1.6, 0, Math.PI * 2); ctx.fill();
      }
      for (let i = 0; i < N; i++)
        for (let j = i + 1; j < N; j++) {
          const dx = pts[i].x - pts[j].x, dy = pts[i].y - pts[j].y;
          const d = Math.hypot(dx, dy);
          if (d < 120) {
            ctx.strokeStyle = `rgba(255,255,255,${0.12 * (1 - d / 120)})`;
            ctx.beginPath(); ctx.moveTo(pts[i].x, pts[i].y); ctx.lineTo(pts[j].x, pts[j].y); ctx.stroke();
          }
        }
      raf = requestAnimationFrame(step);
    };
    step();
    return () => { cancelAnimationFrame(raf); window.removeEventListener("resize", resize); };
  }, []);
  return <canvas ref={ref} className="slide" style={{ background: "#0b0b0b", width: "100%", height: "100%" }} />;
}

export default function HeroBackground({ mode }) {
  if (mode === "video")
    return (
      <video
        className="slide"
        autoPlay muted loop playsInline
        style={{ objectFit: "cover", width: "100%", height: "100%" }}
      >
        <source src={site.heroVideo} type="video/mp4" />
      </video>
    );
  if (mode === "particles") return <Particles />;
  if (mode === "color") return <div className="slide" style={{ background: "#111214" }} />;
  return <div className="slide" style={{ backgroundImage: `url("${site.heroBg}")` }} />;
}
