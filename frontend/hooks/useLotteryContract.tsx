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

  const { data: getTicketCountData, refetch: refetchTicketCount } =
    useReadContract({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "getTicketCount",
      args: [address ?? ZERO_ADDRESS],
      query: { enabled: isContractConfigured && !!address },
    });

  const { data: maxTicketsData } = useReadContract({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    functionName: "maxTickets",
    query: { enabled: isContractConfigured },
  });

  const { data: committedHashData, refetch: refetchCommittedHash } =
    useReadContract({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "committedHash",
      query: { enabled: isContractConfigured },
    });

  useWatchContractEvent({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    eventName: "TicketPurchased",
    onLogs() {
      refetchLotteryInfo();
      refetchTicketCount();
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
      refetchLotteryInfo();
      refetchCommittedHash();
    },
  });

  useWatchContractEvent({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    eventName: "WinnerDrawn",
    onLogs() {
      refetchLotteryInfo();
    },
  });

  useWatchContractEvent({
    address: LOTTERY_CONTRACT_ADDRESS,
    abi: LOTTERY_ABI,
    eventName: "PrizeClaimed",
    onLogs() {
      refetchLotteryInfo();
    },
  });

  const { writeContractAsync: writeBuyTicket, isPending: isEntering } =
    useWriteContract();
  const {
    writeContractAsync: writeBatchBuyTickets,
    isPending: isBatchEntering,
  } = useWriteContract();
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
  const maxTickets = Number(
    (maxTicketsData as bigint | undefined) ?? BigInt(0),
  );
  const userTicketCount = Number(
    (getTicketCountData as bigint | undefined) ?? BigInt(0),
  );
  const committedHash =
    (committedHashData as `0x${string}` | undefined) ?? "0x0";

  const phaseLabel = PHASE_LABELS[phase] ?? `Unknown (${phase})`;
  const ticketPrice = ticketPriceWei ? formatEther(ticketPriceWei) : "0";
  const prizePool = formatEther(prizePoolWei);

  // User limit configuration
  const MAX_TICKETS_PER_USER = 10;
  const canBuyTickets = userTicketCount < MAX_TICKETS_PER_USER;

  const isManager =
    isConnected && !!address && address.toLowerCase() === owner.toLowerCase();
  const canClaimPrize =
    isConnected &&
    !!address &&
    address.toLowerCase() === winningAddress.toLowerCase() &&
    prizePoolWei > BigInt(0);

  const waitForSuccessfulReceipt = async (hash: `0x${string}`) => {
    if (!publicClient) return;

    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status !== "success") {
      throw new Error("Transaction reverted.");
    }
  };

  const buyTicket = async () => {
    if (!isContractConfigured)
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    if (!canBuyTickets) throw new Error("Ticket limit per user reached.");
    const tx = await writeBuyTicket({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "buyTicket",
      value: ticketPriceWei,
    });
    await waitForSuccessfulReceipt(tx);
    refetchLotteryInfo();
    refetchTicketCount();
  };

  const batchBuyTickets = async (amount: number) => {
    if (!isContractConfigured) throw new Error("Contract not configured.");
    if (userTicketCount + amount > MAX_TICKETS_PER_USER)
      throw new Error("Exceeds ticket limit per user.");
    const tx = await writeBatchBuyTickets({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "batchBuyTickets",
      args: [BigInt(amount)],
      value: ticketPriceWei * BigInt(amount),
    });
    await waitForSuccessfulReceipt(tx);
    refetchLotteryInfo();
    refetchTicketCount();
  };

  const claimPrize = async () => {
    if (!isContractConfigured)
      throw new Error("Set LOTTERY_CONTRACT_ADDRESS in lib/contract.ts first.");
    const tx = await writeClaimPrize({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "claimPrize",
    });
    await waitForSuccessfulReceipt(tx);
    refetchLotteryInfo();
  };

  const closeSale = async () => {
    if (!isContractConfigured) throw new Error("Contract not configured.");
    const tx = await writeCloseSale({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "closeSale",
    });
    await waitForSuccessfulReceipt(tx);
    refetchLotteryInfo();
  };

  const commitHash = async (hash: `0x${string}`) => {
    if (!isContractConfigured) throw new Error("Contract not configured.");
    const tx = await writeCommitHash({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "commitHash",
      args: [hash],
    });
    await waitForSuccessfulReceipt(tx);
    refetchLotteryInfo();
    refetchCommittedHash();
  };

  const revealAndDraw = async (secret: `0x${string}`) => {
    if (!isContractConfigured) throw new Error("Contract not configured.");
    const tx = await writeRevealAndDraw({
      address: LOTTERY_CONTRACT_ADDRESS,
      abi: LOTTERY_ABI,
      functionName: "revealAndDraw",
      args: [secret],
    });
    await waitForSuccessfulReceipt(tx);
    refetchLotteryInfo();
    // refetchPendingWithdrawals();
  };

  return {
    phase,
    ticketsSold,
    maxTickets,
    prizePool,
    ticketPrice,
    winningAddress,
    userTicketCount,
    MAX_TICKETS_PER_USER,
    canBuyTickets,
    canClaimPrize,
    isManager,
    isConnected,
    address,
    phaseLabel,
    committedHash,
    isEntering,
    isBatchEntering,
    isClaiming,
    isClosing,
    isCommitting,
    isDrawing,
    isContractConfigured,
    buyTicket,
    batchBuyTickets,
    claimPrize,
    closeSale,
    commitHash,
    revealAndDraw,
  };
}
