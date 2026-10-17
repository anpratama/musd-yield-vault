import type { Abi } from "viem";
import { useReadContract, useReadContracts } from "wagmi";
import vaultAbiJson from "../abis/vault.json";
import strategyAbiJson from "../abis/strategy.json";
import { mezoTestnet } from "../lib/chain";

export const vaultAbi = vaultAbiJson as Abi;
export const strategyAbi = strategyAbiJson as Abi;

const CHAIN_ID = mezoTestnet.id;

export function useVaultCore(vault: string | undefined) {
  const enabled = !!vault;
  const address = vault as `0x${string}` | undefined;

  const { data: totalAssets, refetch: refetchAssets } = useReadContract({
    address,
    abi: vaultAbi,
    functionName: "totalAssets",
    chainId: CHAIN_ID,
    query: { enabled, refetchInterval: 20_000 },
  });
  const { data: totalSupply } = useReadContract({
    address,
    abi: vaultAbi,
    functionName: "totalSupply",
    chainId: CHAIN_ID,
    query: { enabled, refetchInterval: 20_000 },
  });
  const { data: sharePrice } = useReadContract({
    address,
    abi: vaultAbi,
    functionName: "convertToAssets",
    args: [10n ** 18n],
    chainId: CHAIN_ID,
    query: { enabled, refetchInterval: 20_000 },
  });
  const { data: paused } = useReadContract({
    address,
    abi: vaultAbi,
    functionName: "paused",
    chainId: CHAIN_ID,
    query: { enabled, refetchInterval: 20_000 },
  });

  return {
    totalAssets: totalAssets as bigint | undefined,
    totalSupply: totalSupply as bigint | undefined,
    sharePrice: sharePrice as bigint | undefined,
    paused: paused as boolean | undefined,
    refetchAssets,
  };
}

export interface StrategyRow {
  address: string;
  active: boolean;
  targetBps: bigint;
  cap: bigint;
  assets: bigint | undefined;
}

/** Enumerate registered strategies (probe indices until the first revert). */
export function useStrategies(vault: string | undefined): {
  rows: StrategyRow[];
  loading: boolean;
} {
  const enabled = !!vault;
  const address = vault as `0x${string}` | undefined;

  const listCalls = Array.from({ length: 10 }, (_, i) => ({
    address: address!,
    abi: vaultAbi,
    functionName: "strategyList",
    args: [BigInt(i)],
    chainId: CHAIN_ID,
  }));
  const { data: listData, isLoading: listLoading } = useReadContracts({
    contracts: listCalls,
    query: { enabled },
  });

  const addrs: string[] =
    listData
      ?.filter((r) => r.status === "success")
      .map((r) => r.result as string) ?? [];

  const infoCalls = addrs.flatMap((a) => [
    {
      address: address!,
      abi: vaultAbi,
      functionName: "strategies",
      args: [a as `0x${string}`],
      chainId: CHAIN_ID,
    },
    {
      address: a as `0x${string}`,
      abi: strategyAbi,
      functionName: "totalAssets",
      chainId: CHAIN_ID,
    },
  ]);
  const { data: infoData, isLoading: infoLoading } = useReadContracts({
    contracts: infoCalls,
    query: { enabled: enabled && addrs.length > 0, refetchInterval: 20_000 },
  });

  const rows: StrategyRow[] = addrs.map((a, i) => {
    const info = infoData?.[i * 2];
    const assets = infoData?.[i * 2 + 1];
    const tuple = (info?.status === "success" ? info.result : undefined) as
      | [boolean, bigint, bigint]
      | undefined;
    return {
      address: a,
      active: tuple?.[0] ?? false,
      targetBps: tuple?.[1] ?? 0n,
      cap: tuple?.[2] ?? 0n,
      assets:
        assets?.status === "success" ? (assets.result as bigint) : undefined,
    };
  });

  return { rows, loading: listLoading || infoLoading };
}
