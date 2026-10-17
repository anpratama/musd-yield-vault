"use client";

import { useAccount, useReadContract } from "wagmi";
import type { Abi } from "viem";
import vaultAbiJson from "../abis/vault.json";
import erc20AbiJson from "../abis/erc20.json";
import { mezoTestnet } from "../lib/chain";
import { MUSD_ADDRESS, type DeploymentInfo } from "../lib/config";
import { useApyEstimate } from "../lib/apy";
import { useVaultCore } from "../lib/vault";
import { fmtApy, fmtMusd, fmtSharePrice, fmtShares } from "../lib/format";

const vaultAbi = vaultAbiJson as Abi;
const erc20Abi = erc20AbiJson as Abi;

function Stat({
  label,
  value,
  sub,
}: {
  label: string;
  value: string;
  sub?: string;
}) {
  return (
    <div className="card">
      <div className="text-sm font-medium text-slate-500">{label}</div>
      <div className="mt-1 text-2xl font-bold tracking-tight">{value}</div>
      {sub && <div className="mt-1 text-xs text-slate-400">{sub}</div>}
    </div>
  );
}

export function Stats({
  vault,
  deployment,
}: {
  vault: string;
  deployment: DeploymentInfo | null;
}) {
  const { address: user } = useAccount();
  const { totalAssets, sharePrice, paused } = useVaultCore(vault);
  const { apy, collecting } = useApyEstimate(vault, mezoTestnet.id);

  const { data: userShares } = useReadContract({
    address: vault as `0x${string}`,
    abi: vaultAbi,
    functionName: "balanceOf",
    args: user ? [user] : undefined,
    chainId: mezoTestnet.id,
    query: { enabled: !!user, refetchInterval: 20_000 },
  });
  const { data: userAssets } = useReadContract({
    address: vault as `0x${string}`,
    abi: vaultAbi,
    functionName: "convertToAssets",
    args: userShares !== undefined ? [userShares as bigint] : undefined,
    chainId: mezoTestnet.id,
    query: { enabled: userShares !== undefined, refetchInterval: 20_000 },
  });
  const { data: musdBalance } = useReadContract({
    address: MUSD_ADDRESS as `0x${string}`,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: user ? [user] : undefined,
    chainId: mezoTestnet.id,
    query: { enabled: !!user, refetchInterval: 20_000 },
  });

  return (
    <div>
      {paused && (
        <div className="mb-4 rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-800">
          The vault is currently <strong>paused</strong>: deposits are disabled,
          but withdrawals remain open at all times.
        </div>
      )}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat
          label="Total Value Locked"
          value={`${fmtMusd(totalAssets)} MUSD`}
        />
        <Stat
          label="Share price"
          value={`${fmtSharePrice(sharePrice)} MUSD`}
          sub="per yvMUSD"
        />
        <Stat
          label="Est. APY"
          value={collecting ? "Collecting…" : fmtApy(apy)}
          sub={
            collecting
              ? "Live on-chain data — check back after some history accumulates"
              : "Annualized from totalAssets growth"
          }
        />
        <Stat
          label="Your position"
          value={
            user
              ? `${fmtMusd(userAssets as bigint | undefined)} MUSD`
              : "—"
          }
          sub={
            user
              ? `${fmtShares(userShares as bigint | undefined)} yvMUSD · wallet ${fmtMusd(musdBalance as bigint | undefined)} MUSD`
              : "Connect wallet to see your position"
          }
        />
      </div>
    </div>
  );
}
