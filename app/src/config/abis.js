// Minimal ABIs for the Account integration (SOP step 2) — only the functions the UI calls.

export const accountsAbi = [
  {
    type: "function",
    name: "isUser",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    name: "root",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }],
  },
  {
    type: "function",
    name: "getUser",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "registered", type: "bool" },
          { name: "sponsor", type: "address" },
          { name: "directCount", type: "uint256" },
          { name: "lineParent", type: "address" },
          { name: "lineChild", type: "address" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "getAffiliate",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      { name: "referral", type: "address" },
      { name: "directCount", type: "uint256" },
    ],
  },
  {
    type: "function",
    name: "getChildren",
    stateMutability: "view",
    inputs: [
      { name: "user", type: "address" },
      { name: "offset", type: "uint256" },
      { name: "limit", type: "uint256" },
    ],
    outputs: [
      { name: "result", type: "address[]" },
      { name: "total", type: "uint256" },
    ],
  },
  {
    // public mapping getter: line(address) => (parent, child) of the global one-line
    type: "function",
    name: "line",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [
      { name: "parent", type: "address" },
      { name: "child", type: "address" },
    ],
  },
  {
    // public counter: totalUsers() => number of registered accounts (root included)
    type: "function",
    name: "totalUsers",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
];

export const rewardsAbi = [
  {
    type: "function",
    name: "register",
    stateMutability: "nonpayable",
    inputs: [{ name: "sponsor", type: "address" }],
    outputs: [],
  },
  {
    type: "function",
    name: "activate",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "isActive",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    name: "getUser",
    stateMutability: "view",
    inputs: [{ name: "u", type: "address" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "registered", type: "bool" },
          { name: "activated", type: "bool" },
          { name: "rank", type: "uint8" },
          { name: "incomeCap", type: "uint256" },
          { name: "tokenBalance", type: "uint256" },
          { name: "pendingDaily", type: "uint256" },
          { name: "pendingDirect", type: "uint256" },
          { name: "pendingLine", type: "uint256" },
        ],
      },
    ],
  },
  {
    // public mapping getter: overrideTotal(address) => lifetime rank-differential override
    // commission paid (USDT, 18dp). Override is paid instantly to the vault, so this is a total,
    // not a claimable pending.
    type: "function",
    name: "overrideTotal",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    // public mapping getter: directReferralTotal(address) => lifetime direct-referral (L1 sponsor)
    // commission paid (USDT, 18dp). Instant to vault — a total, not a claimable pending.
    type: "function",
    name: "directReferralTotal",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  // Claims — each pays the accrued pending to the caller's vault (or COCT for claimToken).
  { type: "function", name: "claimDailyPassive", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "claimDirectPassive", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "claimLineIncome", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "claimToken", stateMutability: "nonpayable", inputs: [], outputs: [] },
];

export const assetsAbi = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [
      { name: "user", type: "address" },
      { name: "token", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "deposit",
    stateMutability: "nonpayable",
    inputs: [
      { name: "tokenAddress", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "withdraw",
    stateMutability: "nonpayable",
    inputs: [
      { name: "tokenAddress", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
];
