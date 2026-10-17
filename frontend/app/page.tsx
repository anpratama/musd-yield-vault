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
    <header className="border-b border-slate-200 bg-white">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-4">
        <div>
          <h1 className="text-xl font-bold tracking-tight">
            MUSD Yield Vault <span className="text-mezo-600">yvMUSD</span>
          </h1>
          <p className="text-xs text-slate-500">
            ERC-4626 auto-yield vault on Mezo · built for the Mezo Buildathon
          </p>
        </div>
        <div className="flex items-center gap-3">
          <span className="hidden rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-600 sm:inline">
            Mezo Testnet
          </span>
          <ConnectButton showBalance={false} />
        </div>
      </div>
    </header>
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
      <main className="mx-auto max-w-5xl space-y-6 px-4 py-8">
        {deployment === undefined ? (
          <div className="card text-sm text-slate-500">Loading…</div>
        ) : !vault ? (
          <NotDeployed />
        ) : (
          <>
            {wrongNetwork && (
              <div className="card border-amber-300 bg-amber-50">
                <p className="text-sm text-amber-800">
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
              <h2 className="text-lg font-semibold">Contracts</h2>
              <dl className="mt-3 space-y-2 text-sm">
                <div className="flex items-center justify-between gap-4">
                  <dt className="text-slate-500">Vault (yvMUSD)</dt>
                  <dd>
                    <AddressLink address={vault} />
                  </dd>
                </div>
                <div className="flex items-center justify-between gap-4">
                  <dt className="text-slate-500">MUSD (asset)</dt>
                  <dd>
                    <AddressLink address={MUSD_ADDRESS} />
                  </dd>
                </div>
                {deployment.spStrategy && (
                  <div className="flex items-center justify-between gap-4">
                    <dt className="text-slate-500">Stability Pool Strategy</dt>
                    <dd>
                      <AddressLink address={deployment.spStrategy} />
                    </dd>
                  </div>
                )}
                {deployment.mockStrategy && (
                  <div className="flex items-center justify-between gap-4">
                    <dt className="text-slate-500">Mock Yield Strategy</dt>
                    <dd>
                      <AddressLink address={deployment.mockStrategy} />
                    </dd>
                  </div>
                )}
              </dl>
            </div>
          </>
        )}

        <footer className="pt-4 text-center text-xs text-slate-400">
          MUSD Yield Vault · Mezo Buildathon (Track 1: DeFi) · Mezo testnet
          (chain 31611) · contracts unaudited — hackathon demo
        </footer>
      </main>
    </div>
  );
}
