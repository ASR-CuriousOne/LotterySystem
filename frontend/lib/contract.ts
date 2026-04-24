import type { Abi } from "viem";
import LotteryArtifact from "@/Lottery.json";

// Make sure you replace this with the real address if needed or leave it as is if it matches your deployment
export const LOTTERY_CONTRACT_ADDRESS =
  "0x5FbDB2315678afecb367f032d93F642f64180aa3";

export const LOTTERY_ABI = LotteryArtifact.abi as Abi;
