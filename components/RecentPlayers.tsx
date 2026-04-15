import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Crown, Loader2, User } from "lucide-react";
import { toast } from "sonner";
import { useLotteryContract } from "@/hooks/useLotteryContract";

function truncateAddress(addr: string) {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

export function RecentPlayers() {
  const { players, isManager, isPicking, pickWinner } = useLotteryContract();

  const handlePickWinner = async () => {
    try {
      await pickWinner();
      toast.success("Winner picked! 🎉");
    } catch {
      toast.error("Failed to pick winner");
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
          <Button
            variant="outline"
            onClick={handlePickWinner}
            disabled={isPicking || players.length === 0}
            className="w-full border-accent/30 font-mono text-accent hover:bg-accent/10 hover:text-accent"
          >
            {isPicking ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Picking...
              </>
            ) : (
              <>
                <Crown className="mr-2 h-4 w-4" />
                Pick Winner (Admin)
              </>
            )}
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
