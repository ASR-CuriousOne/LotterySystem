import type { Abi } from "viem";
import LotteryArtifact from "@/Lottery.json";

export const LOTTERY_CONTRACT_ADDRESS = (process.env
  .NEXT_PUBLIC_LOTTERY_CONTRACT_ADDRESS ||
  "0x5FbDB2315678afecb367f032d93F642f64180aa3") as `0x${string}`;

export const LOTTERY_ABI = LotteryArtifact.abi as Abi;
