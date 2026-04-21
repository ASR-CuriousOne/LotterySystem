import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Crown, Loader2, ShieldAlert, User } from "lucide-react";
import { toast } from "sonner";
import { useLotteryContract } from "@/hooks/useLotteryContract";

function truncateAddress(addr: string) {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

export function RecentPlayers() {
  const {
    players,
    isManager,
    isPicking,
    pickWinner,
    roundMeta,
    upkeepNeeded,
    enableRefundFallback,
    isEnablingRefundFallback,
  } = useLotteryContract();

  const handlePickWinner = async () => {
    try {
      await pickWinner();
      toast.success("Upkeep submitted", {
        description:
          "Randomness request flow has been triggered for this round.",
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Please try again.";
      toast.error("Failed to perform upkeep", {
        description: message,
      });
    }
  };

  const handleEnableRefundFallback = async () => {
    try {
      await enableRefundFallback();
      toast.success("Refund fallback enabled", {
        description: "Users can now claim ticket refunds for the stuck round.",
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Please try again.";
      toast.error("Failed to enable refund fallback", {
        description: message,
      });
    }
  };

  return (
    <Card className="border-border/30 bg-card/80 backdrop-blur">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="font-mono text-lg text-foreground">
          Recent Players
        </CardTitle>
        <span className="rounded-md bg-secondary px-2 py-0.5 font-mono text-xs text-muted-foreground">
          {players.length} entered
        </span>
      </CardHeader>

      <CardContent className="space-y-4">
        {players.length === 0 ? (
          <p className="py-4 text-center text-sm text-muted-foreground">
            No players yet. Be the first!
          </p>
        ) : (
          <ul className="space-y-2">
            {players.map((addr, i) => (
              <li
                key={`${addr}-${i}`}
                className="flex items-center gap-2 rounded-md border border-border/30 bg-secondary/30 px-3 py-2 font-mono text-sm text-secondary-foreground"
              >
                <User className="h-3.5 w-3.5 text-muted-foreground" />
                {truncateAddress(addr)}
              </li>
            ))}
          </ul>
        )}

        {isManager && (
          <div className="space-y-2">
            <p className="text-xs text-muted-foreground">
              Operator flow for the current round.
            </p>
            <p className="rounded-md border border-border/40 bg-secondary/30 px-2 py-1 font-mono text-xs text-muted-foreground">
              Round {roundMeta.currentRoundId} • {roundMeta.phaseLabel} •
              upkeepNeeded={upkeepNeeded ? "true" : "false"}
            </p>
            <Button
              variant="outline"
              onClick={handlePickWinner}
              disabled={isPicking || !upkeepNeeded}
              className="w-full border-accent/30 font-mono text-accent hover:bg-accent/10 hover:text-accent"
            >
              {isPicking ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Processing...
                </>
              ) : (
                <>
                  <Crown className="mr-2 h-4 w-4" />
                  Perform Upkeep (Admin)
                </>
              )}
            </Button>
            <Button
              variant="outline"
              onClick={handleEnableRefundFallback}
              disabled={isEnablingRefundFallback}
              className="w-full border-destructive/30 font-mono text-destructive hover:bg-destructive/10 hover:text-destructive"
            >
              {isEnablingRefundFallback ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Processing...
                </>
              ) : (
                <>
                  <ShieldAlert className="mr-2 h-4 w-4" />
                  Enable Refund Fallback
                </>
              )}
            </Button>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
