import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { formatEther, type Address } from "viem";
import {
  LOTTERY_ABI,
  LOTTERY_CONTRACT_ADDRESS,
  TICKET_PRICE_ETH,
} from "@/lib/contract";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

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
  const { writeContractAsync: writeCloseSale, isPending: isPicking } =
    useWriteContract();

  const manager = (ownerData as Address | undefined) ?? ZERO_ADDRESS;
  const lotteryInfo = lotteryInfoData as LotteryInfoTuple | undefined;
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

  const ticketPrice = ticketPriceWei
    ? formatEther(ticketPriceWei)
    : TICKET_PRICE_ETH;
  const prizePool = formatEther(prizePoolWei);

  const isManager =
    isConnected && !!address && address.toLowerCase() === manager.toLowerCase();

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

    await writeCloseSale({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "closeSale",
    });
  };

  return {
    players,
    manager,
    prizePool,
    ticketPrice,
    isManager,
    isConnected,
    address,
    isEntering,
    isPicking,
    isContractConfigured,
    enterLottery,
    pickWinner: pickWinnerFn,
  };
}
