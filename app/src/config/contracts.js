// COC contract addresses by chainId (SOP step 3).
// 56    = BSC mainnet — the LIVE COC deployment (accounts/assets/rewards). COCT token 0x13c6f832…A77.
// 31337 = the shared NAS anvil (192.168.100.79:8545) dev deployment — re-run
//         chain/script/coc/deploy-local.sh with RPC=http://192.168.100.79:8545 and update these if the
//         node is reset (addresses depend on the deployer's nonce on the shared node).
export const CONTRACTS_BY_CHAIN = {
  56: {
    accounts: "0x640bD58A901523039FD134d1d91419Cdf218b26D",
    assets: "0x6e12a69750DF8907Cc63Eb11ddA485AdD6Ba3317",
    rewards: "0x5D76ab80f010f9d8091a3D06dace9111D7d0e8de",
    liquidity: "0xBf946e19cc916C63dB0d348786d4402cC03410B9",
  },
  31337: {
    accounts: "0x2B0d36FACD61B71CC05ab8F3D2355ec3631C0dd5",
    assets: "0xfbC22278A96299D91d41C453234d97b4F5Eb9B2d",
    rewards: "0x46b142DD1E924FAb83eCc3c08e4D46E82f005e0E",
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
