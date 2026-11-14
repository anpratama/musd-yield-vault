"use client";

import { useState } from "react";
import {
  darkTheme,
  getDefaultConfig,
  RainbowKitProvider,
} from "@rainbow-me/rainbowkit";
import { WagmiProvider } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { mezoTestnet } from "../lib/chain";
import "@rainbow-me/rainbowkit/styles.css";

const config = getDefaultConfig({
  appName: "MUSD Yield Vault",
  // Optional: add your WalletConnect project id in .env for full wallet list.
  // Injected wallets (MetaMask, Rabby, etc.) work without it.
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "demo-project-id",
  chains: [mezoTestnet],
  ssr: true,
});

// Reflex-style UI is dark-only; keep the wallet UI dark with a Mezo-orange accent.
const theme = darkTheme({
  accentColor: "#f97316",
  accentColorForeground: "#ffffff",
  borderRadius: "large",
});

export function Providers({ children }: { children: React.ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={theme}>{children}</RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
