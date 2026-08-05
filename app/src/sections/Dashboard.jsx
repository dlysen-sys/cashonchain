import { useAccount, useReadContract } from "wagmi";
import { useTheme } from "../theme/ThemeContext.jsx";
import { site } from "../data/site.js";
import HeroBackground from "../components/HeroBackground.jsx";
import Typed from "../components/Typed.jsx";
import { contractsFor, readChainId } from "../config/contracts.js";
import { accountsAbi } from "../config/abis.js";

// Odometer style: 5 → "0,000,005" — zero-padded to 7 digits, comma-grouped (grows past 7 as needed).
function formatUserCount(n) {
  const digits = String(Math.max(0, Math.trunc(n))).padStart(7, "0");
  return digits.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

export default function Home() {
  const { bg } = useTheme();

  // Live registered-user count from COCTAccounts (reads even when disconnected — see readChainId).
  const { chainId } = useAccount();
  const readChain = readChainId(chainId);
  const rc = contractsFor(readChain);
  const { data: totalUsers } = useReadContract({
    address: rc?.accounts,
    abi: accountsAbi,
    functionName: "totalUsers",
    chainId: readChain,
    query: { enabled: !!rc, refetchInterval: 30_000 },
  });
  const userCount = formatUserCount(totalUsers != null ? Number(totalUsers) : 0);

  return (
    <div className="card-inner card-started active" id="home-card" style={{ height: "100vh" }}>
      <HeroBackground mode={bg} />
      <div className="centrize full-width">
        <div className="vertical-center">
          {site.logo && (
            <img
              className="coc-hero-logo"
              src={site.logo}
              alt={`${site.name.first}${site.name.last}`}
            />
          )}
          <div className="title">
            <span>{site.name.first}</span><br/>{site.name.last}
          </div>
          <div
            className="subtitle"
            style={{ display: "flex", gap: 10, justifyContent: "center", alignItems: "center" }}
          >
            <Typed words={site.roles} />
          </div>
          <div
            className="subtitle"
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 6,
              marginTop: 24,
            }}
          >
            <span
              style={{
                fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
                fontSize: 38,
                fontWeight: 700,
                letterSpacing: "0.14em",
                lineHeight: 1,
              }}
            >
              {userCount}
            </span>
            <span
              style={{
                fontSize: 12,
                letterSpacing: "0.5em",
                paddingLeft: "0.5em",
                textTransform: "uppercase",
                opacity: 0.65,
              }}
            >
              Users
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
