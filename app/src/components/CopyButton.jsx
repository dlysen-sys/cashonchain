import { useState } from "react";

// Copy-to-clipboard icon button. Swaps to a check for ~1.6s after a successful copy, and stays silent
// when the clipboard is blocked (insecure origin, denied permission) — the value is always on screen
// anyway. Shared by the Tree page's member rows and the Wallet page's manual add-token modal.
//
// `label` renders text beside the icon (modal variant); omit it for the bare icon (table rows).
export default function CopyButton({ value, label, title, className = "coc-tree__copy" }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(String(value));
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      /* clipboard blocked — nothing to do, the value stays on screen */
    }
  };

  if (value === undefined || value === null || value === "") return null;
  const what = title ?? value;

  return (
    <button
      type="button"
      className={className}
      onClick={copy}
      title={copied ? "Copied" : `Copy ${what}`}
      aria-label={copied ? "Copied" : `Copy ${what}`}
    >
      <i className={copied ? "la la-check" : "la la-copy"}></i>
      {label && <span>{copied ? "Copied" : label}</span>}
    </button>
  );
}
