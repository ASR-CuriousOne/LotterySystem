import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Loader2,
  Ticket,
  Trophy,
  Users,
  Coins,
  Wallet,
  Settings,
} from "lucide-react";
import { toast } from "sonner";
import { useLotteryContract } from "@/hooks/useLotteryContract";
import { isTicketSold } from "@/lib/utils";
import { stringToHex, keccak256, encodePacked } from "viem";

function StatBlock({
  icon: Icon,
  label,
  value,
  unit,
  glowClass,
}: {
  icon: React.ElementType;
  label: string;
  value: string;
  unit?: string;
  glowClass?: string;
}) {
  return (
    <div className="flex flex-col items-center gap-1 rounded-lg border border-border/50 bg-secondary/50 p-4">
      <Icon className={`h-5 w-5 text-muted-foreground ${glowClass ?? ""}`} />
      <span className="text-xs uppercase tracking-wider text-muted-foreground">
        {label}
      </span>
      <span className="font-mono text-2xl font-bold text-foreground">
        {value}
        {unit && (
          <span className="ml-1 text-sm text-muted-foreground">{unit}</span>
        )}
      </span>
    </div>
  );
}

export function LotteryTerminal() {
  const [ticketIndex, setTicketIndex] = useState(0);
  const [secretPhrase, setSecretPhrase] = useState("");

  const {
    ticketsSold,
    prizePool,
    ticketPrice,
    isConnected,
    isEntering,
    isClaiming,
    canWithdraw,
    pendingWithdrawals,
    phase,
    phaseLabel,
    ticketBitmap,
    isManager,
    isClosing,
    isCommitting,
    isDrawing,
    isContractConfigured,
    buyTicket,
    claimPrize,
    closeSale,
    commitHash,
    revealAndDraw,
  } = useLotteryContract();

  const handleBuy = async () => {
    try {
      await buyTicket(ticketIndex);
      toast.success("Ticket bought successfully", {
        description: `Ticket #${ticketIndex} is now entered in the draw.`,
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Please try again.";
      toast.error("Transaction failed", {
        description: message,
      });
    }
  };

  const handleClaim = async () => {
    try {
      await claimPrize();
      toast.success("Withdraw submitted!", {
        description: "Your pending vault balance is being withdrawn.",
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Please try again.";
      toast.error("Claim failed", {
        description: message,
      });
    }
  };

  const handleCloseSale = async () => {
    try {
      await closeSale();
      toast.success("Sale closed successfully");
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Please try again.";
      toast.error("Close Sale failed", {
        description: message,
      });
    }
  };

  const handleCommitHash = async () => {
    if (!secretPhrase) return;
    try {
      const bytes32Secret = stringToHex(secretPhrase, { size: 32 });
      const hash = keccak256(encodePacked(["bytes32"], [bytes32Secret]));
      await commitHash(hash);
      toast.success("Hash committed successfully");
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Please try again.";
      toast.error("Commit failed", {
        description: message,
      });
    }
  };

  const handleRevealAndDraw = async () => {
    if (!secretPhrase) return;
    try {
      const bytes32Secret = stringToHex(secretPhrase, { size: 32 });
      await revealAndDraw(bytes32Secret);
      toast.success("Winner drawn!");
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Please try again.";
      toast.error("Reveal & Draw failed", {
        description: message,
      });
    }
  };

  return (
    <Card className="glow-strong border-border/30 bg-card/80 backdrop-blur">
      <CardHeader className="text-center">
        <CardTitle className="font-mono text-2xl tracking-tight text-foreground">
          <span className="text-glow text-primary">◆</span> LOTTERY TERMINAL{" "}
          <span className="text-glow text-primary">◆</span>
        </CardTitle>
      </CardHeader>

      <CardContent className="space-y-6">
        {/* Stats Grid */}
        <div className="grid grid-cols-3 gap-3">
          <StatBlock
            icon={Trophy}
            label="Prize Pool"
            value={prizePool}
            unit="ETH"
          />
          <StatBlock
            icon={Coins}
            label="Ticket Price"
            value={ticketPrice}
            unit="ETH"
          />
          <StatBlock
            icon={Users}
            label="Tickets Sold"
            value={String(ticketsSold)}
          />
        </div>

        <div className="rounded-lg border border-border/50 bg-secondary/40 p-3 text-sm text-center font-medium text-foreground">
          Phase: {phase} • {phaseLabel}
        </div>

        {/* Buy Area */}
        <div className="space-y-3 rounded-lg border border-border/50 bg-muted/30 p-4">
          {!isConnected ? (
            <div className="py-6 text-center">
              <Ticket className="mx-auto mb-2 h-8 w-8 text-muted-foreground" />
              <p className="text-sm text-muted-foreground">
                Connect your wallet to enter the lottery
              </p>
            </div>
          ) : (
            <>
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <label className="text-sm font-medium text-foreground whitespace-nowrap">
                    Select a Ticket
                  </label>
                  <span className="font-mono text-sm text-primary whitespace-nowrap">
                    Cost {ticketPrice} ETH
                  </span>
                </div>
                <div className="grid grid-cols-8 gap-2 max-h-[220px] overflow-y-auto p-1 scrollbar-none [&::-webkit-scrollbar]:hidden bg-background/50 rounded border border-border/30">
                  {Array.from({ length: 256 }).map((_, index) => {
                    const sold =
                      ticketBitmap !== undefined
                        ? isTicketSold(ticketBitmap, index)
                        : false;
                    return (
                      <Button
                        key={index}
                        disabled={sold || phase !== 0}
                        variant={
                          ticketIndex === index
                            ? "default"
                            : sold
                              ? "secondary"
                              : "outline"
                        }
                        onClick={() => setTicketIndex(index)}
                        className="font-mono text-xs w-full h-8 p-0 transition-all hover:scale-105"
                        title={
                          sold
                            ? `Ticket #${index} is sold`
                            : `Select Ticket #${index}`
                        }
                      >
                        {index}
                      </Button>
                    );
                  })}
                </div>
              </div>

              <Button
                onClick={handleBuy}
                disabled={
                  isEntering ||
                  !isContractConfigured ||
                  phase !== 0 ||
                  (ticketBitmap !== undefined &&
                    isTicketSold(ticketBitmap, ticketIndex))
                }
                className="w-full bg-primary text-primary-foreground font-mono text-base hover:bg-primary/90 glow-primary transition-all"
                size="lg"
              >
                {isEntering ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Confirm in Wallet...
                  </>
                ) : (
                  <>
                    <Ticket className="mr-2 h-4 w-4" />
                    Buy Ticket #{ticketIndex}
                  </>
                )}
              </Button>

              <div className="space-y-2 rounded-md border border-border/40 bg-secondary/20 p-3">
                <div className="flex items-center justify-between">
                  <p className="text-xs text-muted-foreground">
                    Vault balance: {pendingWithdrawals} ETH
                  </p>
                </div>
                <Button
                  onClick={handleClaim}
                  disabled={isClaiming || !isContractConfigured || !canWithdraw}
                  variant="outline"
                  className="w-full font-mono"
                >
                  {isClaiming ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Confirming...
                    </>
                  ) : (
                    <>
                      <Wallet className="mr-2 h-4 w-4" />
                      Claim Prize
                    </>
                  )}
                </Button>
              </div>
            </>
          )}
        </div>

        {/* Admin Panel */}
        {isManager && (
          <div className="mt-6 rounded-lg border border-primary/40 bg-primary/5 p-4 space-y-4">
            <div className="flex items-center gap-2 mb-2">
              <Settings className="w-5 h-5 text-primary" />
              <h3 className="font-mono text-primary font-bold">Admin Panel</h3>
            </div>

            <div className="flex flex-col gap-2 border-b border-primary/20 pb-3 sm:flex-row sm:items-center sm:justify-between">
              <span className="max-w-full text-sm font-medium whitespace-normal">
                Phase: {phase} ({phaseLabel})
              </span>
              {phase === 0 && (
                <Button
                  onClick={handleCloseSale}
                  disabled={isClosing || !isContractConfigured}
                  size="sm"
                  variant="secondary"
                  className="w-full sm:w-auto"
                >
                  {isClosing ? (
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  ) : null}
                  Close Sale
                </Button>
              )}
            </div>

            {/* Show Secret Input during Phase 1 (SaleClosed) OR Phase 2 (Committed) */}
            {(phase === 1 || phase === 2) && (
              <div className="space-y-3 pt-1">
                <label className="text-xs text-muted-foreground font-medium uppercase tracking-wider">
                  Secret Phrase
                </label>
                <div className="flex flex-col gap-3">
                  <Input
                    type="text"
                    value={secretPhrase}
                    onChange={(e) => setSecretPhrase(e.target.value)}
                    placeholder="Enter your secret phrase..."
                    className="font-mono text-sm bg-background/50 border-primary/30 focus-visible:ring-primary"
                    disabled={isCommitting || isDrawing}
                  />
                  <div className="flex flex-col gap-2 sm:flex-row">
                    {/* If Sale is Closed, we need to Commit */}
                    {phase === 1 && (
                      <Button
                        onClick={handleCommitHash}
                        disabled={
                          !secretPhrase || isCommitting || !isContractConfigured
                        }
                        size="sm"
                        className="w-full bg-primary/20 border border-primary/50 text-primary hover:bg-primary/30 sm:w-auto"
                      >
                        {isCommitting ? (
                          <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        ) : null}
                        Commit Hash
                      </Button>
                    )}

                    {/* If Hash is Committed, we need to Reveal & Draw */}
                    {phase === 2 && (
                      <Button
                        onClick={handleRevealAndDraw}
                        disabled={
                          !secretPhrase || isDrawing || !isContractConfigured
                        }
                        size="sm"
                        className="w-full bg-primary text-primary-foreground hover:bg-primary/90 sm:w-auto"
                      >
                        {isDrawing ? (
                          <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        ) : null}
                        Reveal & Draw
                      </Button>
                    )}
                  </div>
                </div>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
