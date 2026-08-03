import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// SPA — history fallback is on by default in vite dev/preview.
export default defineConfig({
  // Custom apex domain (cashonchain.network) → served from the root, not /<repo>/.
  base: "/",
  plugins: [react()],
  server: {
    port: 5173,
    open: false,
    // Proxy anvil JSON-RPC through the same origin so the browser never calls the NAS private IP
    // directly (Chrome Private Network Access blocks that). The wagmi anvil transport uses `/rpc` in dev.
    proxy: {
      "/rpc": {
        target: "http://192.168.100.79:8545",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/rpc/, ""),
      },
    },
  },
});
