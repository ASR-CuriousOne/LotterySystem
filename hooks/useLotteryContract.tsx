import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { formatEther, keccak256, type Address } from "viem";
import {
  LOTTERY_ABI,
  LOTTERY_CONTRACT_ADDRESS,
  TICKET_PRICE_ETH,
} from "@/lib/contract";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const DRAWN_PHASE = 3;
const SECRET_STORAGE_KEY = "lottery:latest-reveal-secret";

type LotteryInfoTuple = readonly [
  number | bigint,
  bigint,
  bigint,
  bigint,
  Address,
];

function toSafeNumber(value: bigint, fallback = 0) {
  const max = BigInt(Number.MAX_SAFE_INTEGER);
  if (value > max) return fallback;
  return Number(value);
}

export function useLotteryContract() {
  const [isRunningAdminFlow, setIsRunningAdminFlow] = useState(false);
  const [latestRevealSecret, setLatestRevealSecret] = useState<string | null>(
    null,
  );
  const { address, isConnected } = useAccount();
  const isContractConfigured =
    LOTTERY_CONTRACT_ADDRESS.toLowerCase() !== ZERO_ADDRESS;

  const { data: ownerData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "owner",
    query: { enabled: isContractConfigured },
  });

  const { data: prizePoolData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "prizePool",
    query: { enabled: isContractConfigured },
  });

  const { data: ticketPriceData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "ticketPrice",
    query: { enabled: isContractConfigured },
  });

  const { data: lotteryInfoData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "getLotteryInfo",
    query: { enabled: isContractConfigured },
  });

  const { writeContractAsync: writeBuyTicket, isPending: isEntering } =
    useWriteContract();
  const { writeContractAsync: writeRevealAndDraw, isPending: isDrawing } =
    useWriteContract();
  const { writeContractAsync: writeCloseSale, isPending: isClosing } =
    useWriteContract();
  const { writeContractAsync: writeCommitHash, isPending: isCommitting } =
    useWriteContract();
  const { writeContractAsync: writeClaimPrize, isPending: isClaiming } =
    useWriteContract();

  const manager = (ownerData as Address | undefined) ?? ZERO_ADDRESS;
  const lotteryInfo = lotteryInfoData as LotteryInfoTuple | undefined;
  const phase = Number(lotteryInfo?.[0] ?? 0);
  const participantCount = lotteryInfo?.[2] ?? BigInt(0);
  const participantsLength = toSafeNumber(participantCount);

  // The current UI displays players.length, so expose a sized placeholder list.
  const players = Array.from(
    { length: participantsLength },
    (_, index) => `participant-${index + 1}`,
  );

  const ticketPriceWei =
    (ticketPriceData as bigint | undefined) ??
    (lotteryInfo?.[1] as bigint | undefined);

  const prizePoolWei =
    (prizePoolData as bigint | undefined) ??
    (lotteryInfo?.[3] as bigint | undefined) ??
    BigInt(0);
  const winningAddress =
    (lotteryInfo?.[4] as Address | undefined) ?? ZERO_ADDRESS;

  const ticketPrice = ticketPriceWei
    ? formatEther(ticketPriceWei)
    : TICKET_PRICE_ETH;
  const prizePool = formatEther(prizePoolWei);

  const isManager =
    isConnected && !!address && address.toLowerCase() === manager.toLowerCase();
  const isDrawn = phase === DRAWN_PHASE;
  const isWinner =
    isConnected &&
    !!address &&
    address.toLowerCase() === winningAddress.toLowerCase();

  const enterLottery = async (tickets: number) => {
    if (!isContractConfigured) {
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    }

    if (!ticketPriceWei) {
      throw new Error(
        "Ticket price is not loaded from contract yet. Try again in a moment.",
      );
    }

    const totalTickets = Math.max(1, tickets);

    // The contract buys one ticket per call, so we submit one tx per ticket.
    for (let i = 0; i < totalTickets; i += 1) {
      await writeBuyTicket({
        address: LOTTERY_CONTRACT_ADDRESS,
        abi: LOTTERY_ABI,
        functionName: "buyTicket",
        value: ticketPriceWei,
      });
    }
  };

  const pickWinnerFn = async () => {
    if (!isContractConfigured) {
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    }

    setIsRunningAdminFlow(true);

    try {
      const randomBytes = new Uint8Array(32);
      crypto.getRandomValues(randomBytes);
      const secret = `0x${Array.from(randomBytes)
        .map((value) => value.toString(16).padStart(2, "0"))
        .join("")}` as `0x${string}`;

      const hash = keccak256(secret);

      localStorage.setItem(SECRET_STORAGE_KEY, secret);
      setLatestRevealSecret(secret);

      await writeCloseSale({
        address: LOTTERY_CONTRACT_ADDRESS,
        abi: LOTTERY_ABI,
        functionName: "closeSale",
      });

      await writeCommitHash({
        address: LOTTERY_CONTRACT_ADDRESS,
        abi: LOTTERY_ABI,
        functionName: "commitHash",
        args: [hash],
      });

      await writeRevealAndDraw({
        address: LOTTERY_CONTRACT_ADDRESS,
        abi: LOTTERY_ABI,
        functionName: "revealAndDraw",
        args: [secret],
      });
    } finally {
      setIsRunningAdminFlow(false);
    }
  };

  const claimWinnings = async () => {
    if (!isContractConfigured) {
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    }

    await writeClaimPrize({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "claimPrize",
    });
  };

  return {
    players,
    manager,
    phase,
    winningAddress,
    prizePool,
    ticketPrice,
    isManager,
    isDrawn,
    isWinner,
    isConnected,
    address,
    isEntering,
    isPicking: isRunningAdminFlow || isClosing || isCommitting || isDrawing,
    latestRevealSecret,
    isClaiming,
    isContractConfigured,
    enterLottery,
    pickWinner: pickWinnerFn,
    claimWinnings,
  };
}
