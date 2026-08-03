import { useEffect, useRef, useState } from "react";
import "./Typed.css";

// Small type/delete loop over `words` — replaces the original typed-title lib.
export default function Typed({ words, typeSpeed = 90, deleteSpeed = 45, pause = 1400 }) {
  const [text, setText] = useState("");
  const [idx, setIdx] = useState(0);
  const [deleting, setDeleting] = useState(false);
  const timer = useRef();

  useEffect(() => {
    const word = words[idx % words.length];
    let delay;
    if (!deleting && text === word) {
      delay = pause;
      timer.current = setTimeout(() => setDeleting(true), delay);
      return () => clearTimeout(timer.current);
    }
    if (deleting && text === "") {
      setDeleting(false);
      setIdx((i) => (i + 1) % words.length);
      return;
    }
    delay = deleting ? deleteSpeed : typeSpeed;
    timer.current = setTimeout(() => {
      setText((t) =>
        deleting ? word.slice(0, t.length - 1) : word.slice(0, t.length + 1)
      );
    }, delay);
    return () => clearTimeout(timer.current);
  }, [text, deleting, idx, words, typeSpeed, deleteSpeed, pause]);

  return (
    <span style={{ color: "#fff" }}>
      <span>{text}</span>
      <span className="blinking-cursor is-blinking" style={{ color: "inherit" }}>_</span>
    </span>
  );
}
