"use client";

import { LotteryTerminal } from "@/components/LotteryTerminal";
import Navbar from "@/components/Navbar";
import { RecentPlayers } from "@/components/RecentPlayers";

export default function Home() {
  return (
    <div className="flex min-h-screen flex-col bg-background">
      <Navbar />

      {/* Ambient background effect */}
      <div className="pointer-events-none fixed inset-0 overflow-hidden">
        <div className="absolute -top-1/2 left-1/2 h-200 w-200 -translate-x-1/2 rounded-full bg-primary/5 blur-3xl" />
      </div>

      <main className="relative flex-1">
        <div className="container max-w-2xl py-12 space-y-6">
          <div className="text-center space-y-2 mb-8">
            <h1 className="font-mono text-4xl font-bold tracking-tight text-foreground">
              Decentralized{" "}
              <span className="text-glow text-primary">Lottery</span>
            </h1>
            <p className="text-muted-foreground">
              Round-based tickets, automated draw, and refund-safe vault
              withdrawals.
            </p>
          </div>
          <LotteryTerminal />
          <RecentPlayers />
        </div>
      </main>
    </div>
  );
}
