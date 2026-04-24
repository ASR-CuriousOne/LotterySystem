import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Ticket } from "lucide-react";
import { useLotteryContract } from "@/hooks/useLotteryContract";
import { isTicketSold } from "@/lib/utils";

export function RecentPlayers() {
  const { ticketsSold, ticketBitmap } = useLotteryContract();

  const soldTickets: number[] = [];
  for (let i = 0; i < 256; i++) {
    if (isTicketSold(ticketBitmap, i)) {
      soldTickets.push(i);
    }
  }

  return (
    <Card className="border-border/30 bg-card/80 backdrop-blur">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="font-mono text-lg text-foreground">
          Recent Players
        </CardTitle>
        <span className="rounded-md bg-secondary px-2 py-0.5 font-mono text-xs text-muted-foreground">
          {ticketsSold} entered
        </span>
      </CardHeader>

      <CardContent className="space-y-4">
        {soldTickets.length === 0 ? (
          <p className="py-4 text-center text-sm text-muted-foreground">
            No players yet. Be the first!
          </p>
        ) : (
          <ul className="space-y-2">
            {soldTickets.map((ticketId) => (
              <li
                key={ticketId}
                className="flex items-center gap-2 rounded-md border border-border/30 bg-secondary/30 px-3 py-2 font-mono text-sm text-secondary-foreground"
              >
                <Ticket className="h-3.5 w-3.5 text-muted-foreground" />
                Ticket Sold: #{ticketId}
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
