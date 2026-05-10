"use client";

import { RainbowKitProvider } from "@rainbow-me/rainbowkit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ThemeProvider } from "next-themes";
import { useState, useEffect } from "react";
import { WagmiProvider } from "wagmi";

import { Toaster } from "@/components/ui/sonner";
import { config } from "@/lib/wagmi-config";

type Web3ProvidersProps = {
  children: React.ReactNode;
};

export default function Web3Providers({ children }: Web3ProvidersProps) {
  const [queryClient] = useState(() => new QueryClient());
  const [isMounted, setIsMounted] = useState(false);
  // eslint-disable-next-line react-hooks/rules-of-hooks
  useEffect(() => { setIsMounted(true); }, []);

  if (!isMounted) return null;
  return (
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
      <WagmiProvider config={config}>
        <QueryClientProvider client={queryClient}>
          <RainbowKitProvider>
            {children}
            <Toaster />
          </RainbowKitProvider>
        </QueryClientProvider>
      </WagmiProvider>
    </ThemeProvider>
  );
}
