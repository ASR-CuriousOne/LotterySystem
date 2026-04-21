import { useMemo } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { formatEther, type Address } from "viem";
import { LOTTERY_ABI, LOTTERY_CONTRACT_ADDRESS } from "@/lib/contract";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

type RoundTuple = readonly [number, bigint, bigint, Address, bigint, number];

const PHASE_LABELS: Record<number, string> = {
  0: "Open",
  1: "Calculating",
  2: "Drawn",
  3: "Refunding",
};

function toSafeNumber(value: bigint, fallback = 0) {
  const max = BigInt(Number.MAX_SAFE_INTEGER);
  if (value > max) return fallback;
  return Number(value);
}

export function useLotteryContract() {
  const { address, isConnected } = useAccount();
  const isContractConfigured =
    LOTTERY_CONTRACT_ADDRESS.toLowerCase() !== ZERO_ADDRESS;

  const { data: currentRoundIdData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "currentRoundId",
    query: { enabled: isContractConfigured },
  });

  const currentRoundId =
    (currentRoundIdData as bigint | undefined) ?? BigInt(0);
  const previousRoundId =
    currentRoundId > BigInt(0) ? currentRoundId - BigInt(1) : BigInt(0);

  const { data: ticketPriceData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "TICKET_PRICE",
    query: { enabled: isContractConfigured },
  });

  const { data: currentRoundData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "rounds",
    args: [currentRoundId],
    query: { enabled: isContractConfigured },
  });

  const { data: previousRoundData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "rounds",
    args: [previousRoundId],
    query: {
      enabled: isContractConfigured && currentRoundId > BigInt(0),
    },
  });

  const { data: upkeepData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "checkUpkeep",
    args: ["0x"],
    query: { enabled: isContractConfigured },
  });

  const { data: pendingWithdrawalsData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "pendingWithdrawals",
    args: [address ?? ZERO_ADDRESS],
    query: { enabled: isContractConfigured && !!address },
  });

  const { writeContractAsync: writeBuyTicket, isPending: isEntering } =
    useWriteContract();
  const {
    writeContractAsync: writePerformUpkeep,
    isPending: isPerformingUpkeep,
  } = useWriteContract();
  const {
    writeContractAsync: writeEnableRefundFallback,
    isPending: isEnablingRefundFallback,
  } = useWriteContract();
  const { writeContractAsync: writeClaimRefund, isPending: isClaimingRefund } =
    useWriteContract();
  const { writeContractAsync: writeWithdrawPrize, isPending: isWithdrawing } =
    useWriteContract();

  const currentRound = currentRoundData as RoundTuple | undefined;
  const previousRound = previousRoundData as RoundTuple | undefined;
  const phase = Number(currentRound?.[0] ?? 0);
  const ticketsSold = Number(currentRound?.[5] ?? 0);
  const participantsLength = toSafeNumber(BigInt(ticketsSold));

  // The current UI displays players.length, so expose a sized placeholder list.
  const players = Array.from(
    { length: participantsLength },
    (_, index) => `participant-${index + 1}`,
  );

  const ticketPriceWei = (ticketPriceData as bigint | undefined) ?? BigInt(0);

  const prizePoolWei = (currentRound?.[2] as bigint | undefined) ?? BigInt(0);

  const lastRoundWinningAddress =
    (previousRound?.[3] as Address | undefined) ?? ZERO_ADDRESS;
  const pendingWithdrawalsWei =
    (pendingWithdrawalsData as bigint | undefined) ?? BigInt(0);
  const upkeepNeeded = Boolean(
    (upkeepData as readonly [boolean, `0x${string}`] | undefined)?.[0],
  );
  const phaseLabel = PHASE_LABELS[phase] ?? `Unknown (${phase})`;

  const ticketPrice = ticketPriceWei ? formatEther(ticketPriceWei) : "0";
  const prizePool = formatEther(prizePoolWei);
  const pendingWithdrawals = formatEther(pendingWithdrawalsWei);

  // The extended contract has no owner-only admin gate for upkeep/fallback actions.
  const isManager = isConnected;
  const isDrawn = phase === 2;
  const isWinner =
    isConnected &&
    !!address &&
    address.toLowerCase() === lastRoundWinningAddress.toLowerCase();

  const canWithdraw = pendingWithdrawalsWei > BigInt(0);

  const roundMeta = useMemo(
    () => ({
      currentRoundId: currentRoundId.toString(),
      previousRoundId: previousRoundId.toString(),
      phase,
      phaseLabel,
      ticketsSold,
      lastRoundWinningAddress,
      upkeepNeeded,
    }),
    [
      currentRoundId,
      previousRoundId,
      phase,
      phaseLabel,
      ticketsSold,
      lastRoundWinningAddress,
      upkeepNeeded,
    ],
  );

  const enterLottery = async (ticketIndex: number) => {
    if (!isContractConfigured) {
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    }

    if (!ticketPriceWei) {
      throw new Error(
        "Ticket price is not loaded from contract yet. Try again in a moment.",
      );
    }

    if (
      !Number.isInteger(ticketIndex) ||
      ticketIndex < 0 ||
      ticketIndex > 255
    ) {
      throw new Error("Ticket index must be an integer between 0 and 255.");
    }

    await writeBuyTicket({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "buyTicket",
      args: [ticketIndex],
      value: ticketPriceWei,
    });
  };

  const pickWinnerFn = async () => {
    if (!isContractConfigured) {
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    }

    await writePerformUpkeep({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "performUpkeep",
      args: ["0x"],
    });
  };

  const enableRefundFallback = async () => {
    if (!isContractConfigured) {
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    }

    await writeEnableRefundFallback({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "enableRefundFallback",
    });
  };

  const claimRefund = async (roundId: number, ticketIndex: number) => {
    if (!isContractConfigured) {
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    }

    if (!Number.isInteger(roundId) || roundId < 0) {
      throw new Error("Round ID must be a non-negative integer.");
    }

    if (
      !Number.isInteger(ticketIndex) ||
      ticketIndex < 0 ||
      ticketIndex > 255
    ) {
      throw new Error("Ticket index must be an integer between 0 and 255.");
    }

    await writeClaimRefund({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "claimRefund",
      args: [BigInt(roundId), ticketIndex],
    });
  };

  const claimWinnings = async () => {
    if (!isContractConfigured) {
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    }

    await writeWithdrawPrize({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "withdrawPrize",
    });
  };

  return {
    players,
    phase,
    prizePool,
    ticketPrice,
    isManager,
    isDrawn,
    isWinner,
    isConnected,
    address,
    roundMeta,
    ticketsSold,
    pendingWithdrawals,
    canWithdraw,
    upkeepNeeded,
    isEntering,
    isPicking: isPerformingUpkeep,
    isClaiming: isWithdrawing,
    isClaimingRefund,
    isEnablingRefundFallback,
    isContractConfigured,
    enterLottery,
    pickWinner: pickWinnerFn,
    claimRefund,
    enableRefundFallback,
    claimWinnings,
  };
}
