// COC contract addresses by chainId (SOP step 3).
// 56    = BSC mainnet — the LIVE COC deployment (accounts/assets/rewards). COCT token 0x13c6f832…A77.
// 31337 = the shared NAS anvil (192.168.100.79:8545) dev deployment — re-run
//         chain/script/coc/deploy-local.sh with RPC=http://192.168.100.79:8545 and update these if the
//         node is reset (addresses depend on the deployer's nonce on the shared node).
export const CONTRACTS_BY_CHAIN = {
  56: {
    accounts: "0x640bD58A901523039FD134d1d91419Cdf218b26D",
    assets: "0xD2b1583B0A217C85298e95c8c166B93a21989844",
    rewards: "0xF9B3d0aEd01D4956cAC8582bBEbB62A6F0BBD686",
    liquidity: "0xBf946e19cc916C63dB0d348786d4402cC03410B9",
  },
  31337: {
    accounts: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    assets: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
    rewards: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
  },
};

// Read-preference order for PUBLIC (pre-wallet) reads. Explicit because JS iterates numeric object keys
// in ASCENDING order — without this, 31337 (the LAN anvil, unreachable for public visitors) would win
// over 56 (BSC mainnet). Mainnet first, local dev second.
const READ_PRIORITY = [56, 31337];

/// Return the wired contract set for `chainId`, or null if this network has no (complete) deployment.
export function contractsFor(chainId) {
  const c = CONTRACTS_BY_CHAIN[chainId];
  if (!c || !c.accounts || !c.assets || !c.rewards) return null;
  return c;
}

/// Pick a chainId to read from for PUBLIC data that should render even before a wallet connects
/// (e.g. total users on the hero). Prefers the connected chain when it's deployed, otherwise the
/// first chain in CONTRACTS_BY_CHAIN that has a complete deployment (31337 today; 56 once BSC ships).
export function readChainId(preferChainId) {
  if (preferChainId && contractsFor(preferChainId)) return preferChainId;
  for (const id of READ_PRIORITY) {
    if (contractsFor(id)) return id;
  }
  return undefined;
}
