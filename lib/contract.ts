import type { Abi } from "viem";
import LotteryArtifact from "@/Lottery.json";

export const LOTTERY_CONTRACT_ADDRESS =
  "0x5FbDB2315678afecb367f032d93F642f64180aa3";

export const LOTTERY_ABI = LotteryArtifact.abi as Abi;

export const TICKET_PRICE_ETH = "0.01"; // TODO: Replace with actual ticket price
