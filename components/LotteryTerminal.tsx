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
  ChevronUp,
  ChevronDown,
} from "lucide-react";
import { toast } from "sonner";
import { useLotteryContract } from "@/hooks/useLotteryContract";

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
  const [tickets, setTickets] = useState(1);
  const {
    players,
    prizePool,
    ticketPrice,
    isConnected,
    isEntering,
    isClaiming,
    isContractConfigured,
    enterLottery,
    isDrawn,
    isWinner,
    claimWinnings,
  } = useLotteryContract();

  const handleBuy = async () => {
    if (tickets < 1) return;
    try {
      await enterLottery(tickets);
      toast.success(`${tickets} ticket${tickets > 1 ? "s" : ""} purchased!`, {
        description: "Good luck, anon 🍀",
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Please try again.";
      toast.error("Transaction failed", {
        description: message,
      });
    }
  };

  const totalCost = (Number(ticketPrice) * tickets).toFixed(4);
  const canClaimPrize = isConnected && isDrawn && isWinner;

  const handleClaim = async () => {
    try {
      await claimWinnings();
      toast.success("Prize claim submitted!", {
        description: "Check your wallet for confirmation.",
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Please try again.";
      toast.error("Claim failed", {
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
            label="Players"
            value={String(players.length)}
          />
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
              {canClaimPrize && (
                <div className="space-y-3 rounded-md border border-primary/30 bg-primary/5 p-3">
                  <p className="text-center text-sm text-muted-foreground">
                    You are the winning wallet. Claim the prize to withdraw the
                    pool.
                  </p>
                  <Button
                    onClick={handleClaim}
                    disabled={isClaiming || !isContractConfigured}
                    className="w-full bg-primary text-primary-foreground font-mono text-base hover:bg-primary/90 glow-primary transition-all"
                    size="lg"
                  >
                    {isClaiming ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        Confirm in Wallet...
                      </>
                    ) : (
                      <>
                        <Trophy className="mr-2 h-4 w-4" />
                        Claim Prize
                      </>
                    )}
                  </Button>
                </div>
              )}

              <div className="flex items-center gap-3">
                <label className="text-sm text-muted-foreground whitespace-nowrap">
                  Tickets
                </label>
                <div className="relative w-full max-w-44">
                  <Input
                    type="number"
                    min={1}
                    max={100}
                    value={tickets}
                    onChange={(e) =>
                      setTickets(Math.max(1, Number(e.target.value)))
                    }
                    className="font-mono bg-input border-border/50 pr-10"
                  />
                  <div className="absolute inset-y-1 right-1 flex w-7 flex-col overflow-hidden rounded-md border border-border/60 bg-secondary/70">
                    <button
                      type="button"
                      aria-label="Increase tickets"
                      onClick={() =>
                        setTickets((prev) => Math.min(100, prev + 1))
                      }
                      className="flex flex-1 items-center justify-center text-muted-foreground transition-colors hover:bg-primary/20 hover:text-primary"
                    >
                      <ChevronUp className="h-3.5 w-3.5" />
                    </button>
                    <button
                      type="button"
                      aria-label="Decrease tickets"
                      onClick={() =>
                        setTickets((prev) => Math.max(1, prev - 1))
                      }
                      className="flex flex-1 items-center justify-center border-t border-border/60 text-muted-foreground transition-colors hover:bg-primary/20 hover:text-primary"
                    >
                      <ChevronDown className="h-3.5 w-3.5" />
                    </button>
                  </div>
                </div>
                <span className="font-mono text-sm text-muted-foreground whitespace-nowrap">
                  = {totalCost} ETH
                </span>
              </div>

              <Button
                onClick={handleBuy}
                disabled={isEntering || !isContractConfigured}
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
                    Buy Ticket{tickets > 1 ? "s" : ""}
                  </>
                )}
              </Button>
            </>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
