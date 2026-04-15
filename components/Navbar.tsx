import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Gem } from "lucide-react";

export default function Navbar() {
  return (
    <header className="sticky top-0 z-50 border-b border-border/50 bg-background/80 backdrop-blur-xl">
      <div className="container flex h-16 items-center justify-between">
        <div className="flex items-center gap-2">
          <Gem className="h-6 w-6 text-primary" />
          <span className="font-mono text-lg font-bold tracking-tight text-foreground">
            LOTTO<span className="text-primary">X</span>
          </span>
        </div>
        <ConnectButton
          chainStatus="icon"
          showBalance={false}
          accountStatus={{
            smallScreen: "avatar",
            largeScreen: "full",
          }}
        />
      </div>
    </header>
  );
}
