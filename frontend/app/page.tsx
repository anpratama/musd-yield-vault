"use client";

import { useEffect, useState } from "react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount, useChainId, useSwitchChain } from "wagmi";
import { mezoTestnet } from "../lib/chain";
import {
  loadDeployment,
  MUSD_ADDRESS,
  type DeploymentInfo,
} from "../lib/config";
import { Stats } from "../components/Stats";
import { Strategies } from "../components/Strategies";
import { DepositWithdraw } from "../components/DepositWithdraw";
import { NotDeployed } from "../components/NotDeployed";
import { AddressLink } from "../components/ExplorerLink";

function Header() {
  return (
    <header className="sticky top-0 z-40 border-b border-white/5 bg-black/60 backdrop-blur-xl">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-4">
        <div>
          <h1 className="font-display text-xl font-bold tracking-tight">
            MUSD Yield Vault <span className="text-mezo-500">yvMUSD</span>
          </h1>
          <p className="text-xs text-zinc-500">
            ERC-4626 auto-yield vault on Mezo · built for the Mezo Buildathon
          </p>
        </div>
        <div className="flex items-center gap-3">
          <span className="hidden rounded-full border border-white/10 bg-white/5 px-3 py-1 text-xs font-semibold text-zinc-300 sm:inline">
            Mezo Testnet
          </span>
          <ConnectButton showBalance={false} />
        </div>
      </div>
    </header>
  );
}

/**
 * Cinematic hero in the Reflex language: a CSS "black hole" — dark core,
 * glowing accretion ring (slow spin + pulsing halo) — over the headline.
 * Pure CSS, no WebGL, so it stays light on a functional dapp page.
 */
function Hero() {
  return (
    <section className="relative overflow-hidden py-10 text-center sm:py-14">
      <div className="relative mx-auto mb-8 h-36 w-36 sm:h-44 sm:w-44" aria-hidden>
        {/* halo */}
        <div className="absolute inset-0 animate-pulse-glow rounded-full bg-mezo-600/25 blur-3xl" />
        {/* accretion disk */}
        <div
          className="absolute inset-0 animate-spin-slow rounded-full"
          style={{
            background:
              "conic-gradient(from 0deg, transparent 0deg, rgba(253,186,116,0.9) 40deg, rgba(249,115,22,0.15) 120deg, transparent 180deg, rgba(251,146,60,0.7) 230deg, rgba(249,115,22,0.1) 300deg, transparent 360deg)",
            WebkitMask:
              "radial-gradient(farthest-side, transparent calc(100% - 14px), #000 calc(100% - 13px))",
            mask: "radial-gradient(farthest-side, transparent calc(100% - 14px), #000 calc(100% - 13px))",
          }}
        />
        {/* inner rim light */}
        <div className="absolute inset-[13px] rounded-full shadow-[0_0_40px_6px_rgba(249,115,22,0.35)]" />
        {/* event horizon */}
        <div className="absolute inset-[15px] rounded-full bg-black shadow-[inset_0_0_24px_rgba(0,0,0,1)]" />
      </div>

      <h2 className="font-display mx-auto max-w-2xl text-4xl font-bold leading-[1.05] tracking-tight sm:text-5xl">
        Deposit MUSD.
        <br />
        <span className="bg-gradient-to-r from-mezo-300 via-mezo-500 to-mezo-700 bg-clip-text text-transparent">
          Earn automatically.
        </span>
      </h2>
      <p className="mx-auto mt-4 max-w-xl text-sm leading-relaxed text-zinc-400 sm:text-base">
        An ERC-4626 vault that routes your MUSD into Mezo&apos;s Stability Pool
        and harvests the BTC yield for you — no manual claiming, no lockups.
      </p>
      <div className="mt-6 flex flex-wrap items-center justify-center gap-2 text-xs font-medium text-zinc-400">
        <span className="rounded-full border border-white/10 bg-white/5 px-3 py-1">ERC-4626</span>
        <span className="rounded-full border border-white/10 bg-white/5 px-3 py-1">Stability Pool strategy</span>
        <span className="rounded-full border border-white/10 bg-white/5 px-3 py-1">Keeper rebalanced</span>
      </div>
    </section>
  );
}

export default function Home() {
  const [deployment, setDeployment] = useState<DeploymentInfo | null | undefined>(
    undefined
  );
  const chainId = useChainId();
  const { isConnected } = useAccount();
  const { switchChain, isPending: switching } = useSwitchChain();

  useEffect(() => {
    loadDeployment().then(setDeployment);
  }, []);

  const vault = deployment?.vault;
  const wrongNetwork = isConnected && chainId !== mezoTestnet.id;

  return (
    <div className="min-h-screen">
      <Header />
      <main className="mx-auto max-w-5xl space-y-6 px-4 pb-8">
        {deployment === undefined ? (
          <div className="card mt-8 text-sm text-zinc-400">Loading…</div>
        ) : !vault ? (
          <div className="mt-8">
            <NotDeployed />
          </div>
        ) : (
          <>
            <Hero />

            {wrongNetwork && (
              <div className="card border-amber-500/30 bg-amber-500/10">
                <p className="text-sm text-amber-200">
                  You are connected to the wrong network. Please switch to{" "}
                  <strong>Mezo Testnet</strong>.
                </p>
                <button
                  className="btn-primary mt-3"
                  disabled={switching}
                  onClick={() => switchChain({ chainId: mezoTestnet.id })}
                >
                  {switching ? "Switching…" : "Switch to Mezo Testnet"}
                </button>
              </div>
            )}

            <Stats vault={vault} deployment={deployment} />

            <div className="grid gap-6 lg:grid-cols-5">
              <div className="lg:col-span-3">
                <Strategies vault={vault} deployment={deployment} />
              </div>
              <div className="lg:col-span-2">
                <DepositWithdraw vault={vault} />
              </div>
            </div>

            <div className="card">
              <h2 className="font-display text-lg font-semibold">Contracts</h2>
              <dl className="mt-3 space-y-2 text-sm">
                <div className="flex items-center justify-between gap-4">
                  <dt className="text-zinc-500">Vault (yvMUSD)</dt>
                  <dd>
                    <AddressLink address={vault} />
                  </dd>
                </div>
                <div className="flex items-center justify-between gap-4">
                  <dt className="text-zinc-500">MUSD (asset)</dt>
                  <dd>
                    <AddressLink address={MUSD_ADDRESS} />
                  </dd>
                </div>
                {deployment.spStrategy && (
                  <div className="flex items-center justify-between gap-4">
                    <dt className="text-zinc-500">Stability Pool Strategy</dt>
                    <dd>
                      <AddressLink address={deployment.spStrategy} />
                    </dd>
                  </div>
                )}
                {deployment.mockStrategy && (
                  <div className="flex items-center justify-between gap-4">
                    <dt className="text-zinc-500">Mock Yield Strategy</dt>
                    <dd>
                      <AddressLink address={deployment.mockStrategy} />
                    </dd>
                  </div>
                )}
              </dl>
            </div>
          </>
        )}

        <footer className="pt-4 text-center text-xs text-zinc-600">
          MUSD Yield Vault · Mezo Buildathon (Track 1: DeFi) · Mezo testnet
          (chain 31611) · contracts unaudited — hackathon demo
        </footer>
      </main>
    </div>
  );
}
