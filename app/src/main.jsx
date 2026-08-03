import React from "react";
import { createRoot } from "react-dom/client";
import { WagmiProvider } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import App from "./App.jsx";
import { wagmiConfig } from "./lib/appkit.js"; // side effect: createAppKit()
import { captureSponsorFromHash } from "./lib/affiliate.js";
import "./overrides.css";

// Affiliate link (<origin>/#/0x…): capture the sponsor to localStorage and land the visitor on the
// registration form BEFORE the router mounts (avoids racing the index redirect). No-op for normal visits.
if (captureSponsorFromHash()) window.history.replaceState(null, "", "/account");

const queryClient = new QueryClient();

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <App />
      </QueryClientProvider>
    </WagmiProvider>
  </React.StrictMode>
);
