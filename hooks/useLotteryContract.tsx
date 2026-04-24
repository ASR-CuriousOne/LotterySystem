import {
  useAccount,
  useReadContract,
  useWriteContract,
  useWatchContractEvent,
  usePublicClient,
} from "wagmi";
import { formatEther, type Address } from "viem";
import { LOTTERY_ABI, LOTTERY_CONTRACT_ADDRESS } from "@/lib/contract";

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const PHASE_LABELS: Record<number, string> = {
  0: "Open",
  1: "Sale Closed",
  2: "Committed",
  3: "Drawn",
};

export function useLotteryContract() {
  const { address, isConnected } = useAccount();
  const isContractConfigured =
    LOTTERY_CONTRACT_ADDRESS.toLowerCase() !== ZERO_ADDRESS;

  const publicClient = usePublicClient();

  const { data: lotteryInfoData, refetch: refetchLotteryInfo } =
    useReadContract({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "getLotteryInfo",
      query: { enabled: isContractConfigured },
    });

  const { data: ownerData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "owner",
    query: { enabled: isContractConfigured },
  });

  const { data: pendingWithdrawalsData, refetch: refetchPendingWithdrawals } =
    useReadContract({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "pendingWithdrawals",
      args: [address ?? ZERO_ADDRESS],
      query: { enabled: isContractConfigured && !!address },
    });

  const { data: committedHashData, refetch: refetchCommittedHash } =
    useReadContract({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "committedHash",
      query: { enabled: isContractConfigured },
    });

  const { data: ticketBitmapData, refetch: refetchTicketBitmap } =
    useReadContract({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "ticketBitmap",
      query: { enabled: isContractConfigured },
    });

  useWatchContractEvent({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    eventName: "TicketPurchased",
    onLogs() {
      refetchLotteryInfo();
      refetchTicketBitmap();
    },
  });

  useWatchContractEvent({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    eventName: "SaleClosed",
    onLogs() {
      refetchLotteryInfo();
    },
  });

  useWatchContractEvent({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    eventName: "HashCommitted",
    onLogs() {
      refetchCommittedHash();
    },
  });

  useWatchContractEvent({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    eventName: "WinnerDrawn",
    onLogs() {
      refetchLotteryInfo();
      refetchPendingWithdrawals();
    },
  });

  useWatchContractEvent({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    eventName: "PrizeClaimed",
    onLogs() {
      refetchPendingWithdrawals();
    },
  });

  const { writeContractAsync: writeBuyTicket, isPending: isEntering } =
    useWriteContract();
  const { writeContractAsync: writeClaimPrize, isPending: isClaiming } =
    useWriteContract();
  const { writeContractAsync: writeCloseSale, isPending: isClosing } =
    useWriteContract();
  const { writeContractAsync: writeCommitHash, isPending: isCommitting } =
    useWriteContract();
  const { writeContractAsync: writeRevealAndDraw, isPending: isDrawing } =
    useWriteContract();

  const lotteryInfo = lotteryInfoData as
    | readonly [number, bigint, bigint, bigint, Address]
    | undefined;
  const phase = lotteryInfo?.[0] ?? 0;
  const ticketPriceWei = lotteryInfo?.[1] ?? BigInt(0);
  const ticketsSold = Number(lotteryInfo?.[2] ?? 0);
  const prizePoolWei = lotteryInfo?.[3] ?? BigInt(0);
  const winningAddress = lotteryInfo?.[4] ?? ZERO_ADDRESS;

  const owner = (ownerData as Address | undefined) ?? ZERO_ADDRESS;
  const ticketBitmap = (ticketBitmapData as bigint | undefined) ?? BigInt(0);
  const committedHash =
    (committedHashData as `0x${string}` | undefined) ?? "0x0";
  const pendingWithdrawalsWei =
    (pendingWithdrawalsData as bigint | undefined) ?? BigInt(0);

  const phaseLabel = PHASE_LABELS[phase] ?? `Unknown (${phase})`;
  const ticketPrice = ticketPriceWei ? formatEther(ticketPriceWei) : "0";
  const prizePool = formatEther(prizePoolWei);
  const pendingWithdrawals = formatEther(pendingWithdrawalsWei);

  const isManager =
    isConnected && !!address && address.toLowerCase() === owner.toLowerCase();
  const canWithdraw = pendingWithdrawalsWei > BigInt(0);

  const buyTicket = async (ticketIndex: number) => {
    if (!isContractConfigured)
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    const tx = await writeBuyTicket({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "buyTicket",
      args: [ticketIndex],
      value: ticketPriceWei,
    });
    if (publicClient) {
      await publicClient.waitForTransactionReceipt({ hash: tx });
      refetchLotteryInfo();
      refetchTicketBitmap();
    }
  };

  const claimPrize = async () => {
    if (!isContractConfigured)
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    const tx = await writeClaimPrize({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "claimPrize",
    });
    if (publicClient) {
      await publicClient.waitForTransactionReceipt({ hash: tx });
      refetchPendingWithdrawals();
    }
  };

  const closeSale = async () => {
    if (!isContractConfigured) throw new Error("Contract not configured.");
    const tx = await writeCloseSale({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "closeSale",
    });
    if (publicClient) {
      await publicClient.waitForTransactionReceipt({ hash: tx });
      refetchLotteryInfo();
    }
  };

  const commitHash = async (hash: `0x${string}`) => {
    if (!isContractConfigured) throw new Error("Contract not configured.");
    const tx = await writeCommitHash({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "commitHash",
      args: [hash],
    });
    if (publicClient) {
      await publicClient.waitForTransactionReceipt({ hash: tx });
      refetchCommittedHash();
    }
  };

  const revealAndDraw = async (secret: `0x${string}`) => {
    if (!isContractConfigured) throw new Error("Contract not configured.");
    const tx = await writeRevealAndDraw({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "revealAndDraw",
      args: [secret],
    });
    if (publicClient) {
      await publicClient.waitForTransactionReceipt({ hash: tx });
      refetchLotteryInfo();
      refetchPendingWithdrawals();
    }
  };

  return {
    phase,
    ticketsSold,
    prizePool,
    ticketPrice,
    winningAddress,
    ticketBitmap,
    pendingWithdrawals,
    canWithdraw,
    isManager,
    isConnected,
    address,
    phaseLabel,
    committedHash,
    isEntering,
    isClaiming,
    isClosing,
    isCommitting,
    isDrawing,
    isContractConfigured,
    buyTicket,
    claimPrize,
    closeSale,
    commitHash,
    revealAndDraw,
  };
}
