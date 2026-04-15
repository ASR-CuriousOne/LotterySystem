import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { metaMaskWallet } from "@rainbow-me/rainbowkit/wallets";
import { hardhat, sepolia } from "wagmi/chains";

const chains = [sepolia, hardhat] as const;

export const config = getDefaultConfig({
  appName: "Lottery dApp",
  projectId:
    process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ||
    "YOUR_WALLETCONNECT_PROJECT_ID",
  chains,
  wallets: [
    {
      groupName: "Recommended",
      wallets: [metaMaskWallet],
    },
  ],
  ssr: true,
});
