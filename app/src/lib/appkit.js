// Web3 config — Reown AppKit + wagmi adapter. Imported once (side effect) from main.jsx.
// See templates/web3-integration-template.md.
import { createAppKit } from "@reown/appkit/react";
import { WagmiAdapter } from "@reown/appkit-adapter-wagmi";
import { bsc, bscTestnet, defineChain } from "@reown/appkit/networks";

// Reown (WalletConnect) project id — a PUBLIC client identifier, safe in the frontend.
// Set VITE_REOWN_PROJECT_ID for COC's own id; falls back to a shared dev id for local work.
export const projectId =
  import.meta.env.VITE_REOWN_PROJECT_ID || "3114629b3157317b0cf3be442a510ede";

// Shared NAS anvil (chainId 31337, 192.168.100.79:8545). In DEV the browser reads through the
// same-origin Vite `/rpc` proxy — a page on localhost calling the NAS private IP directly is blocked by
// Chrome Private Network Access, which silently fails every read/simulation. Prod hits the node URL.
// See templates/local-chain-template.md + vite.config.js (server.proxy["/rpc"]).
const anvilRpc = import.meta.env.DEV ? `${window.location.origin}/rpc` : "http://192.168.100.79:8545";
export const anvil = defineChain({
  id: 31337,
  caipNetworkId: "eip155:31337",
  chainNamespace: "eip155",
  name: "COC Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [anvilRpc] } },
  testnet: true,
});

// BNB Smart Chain first = default; testnet + local anvil for dev.
export const networks = [bsc, bscTestnet, anvil];

const wagmiAdapter = new WagmiAdapter({ networks, projectId, ssr: false });
export const wagmiConfig = wagmiAdapter.wagmiConfig;

// Token logo handed to the wallet by wallet_watchAsset. Must be an ABSOLUTE public URL — the wallet
// app fetches it from its own context, so window.location.origin would break on localhost.
const TOKEN_IMAGE = "https://cashonchain.network/logo.png";

// Tokens shown on the Wallet page. Addresses are the BSC-mainnet tokens (etched mocks on local anvil).
// `addable` = offer "add to wallet" (EIP-747 wallet_watchAsset) for it; ERC-20 only, native BNB can't.
export const TOKENS = [
  { symbol: "BNB", kind: "native", decimals: 18 },
  {
    symbol: "USDT",
    kind: "erc20",
    address: "0x55d398326f99059fF775485246999027B3197955",
    decimals: 18,
    addable: true,
    image: TOKEN_IMAGE,
  },
  {
    symbol: "COCT",
    kind: "erc20",
    address: "0x13c6f832A8eA9D450FBc04c73b59D2A66ae12A77",
    decimals: 18,
    addable: true,
    image: TOKEN_IMAGE,
  },
];

createAppKit({
  adapters: [wagmiAdapter],
  networks,
  defaultNetwork: bsc,
  projectId,
  metadata: {
    name: "Cash On Chain",
    description: "Cash On Chain — Web3 dApp",
    url: "https://cashonchain.network",
    icons: ["https://cashonchain.network/favicon.ico"],
  },
  themeMode: "dark",
  themeVariables: {
    "--w3m-accent": "#5ac24e", // matches the default green theme accent
    "--w3m-border-radius-master": "3px",
  },
  features: { analytics: false, email: false, socials: false },
});
