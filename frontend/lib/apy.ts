import { useEffect, useRef, useState } from "react";
import { useReadContract } from "wagmi";
import vaultAbi from "../abis/vault.json";

interface Snapshot {
  t: number; // ms epoch
  assets: string; // bigint as string
}

const MAX_SNAPSHOTS = 240;
const MIN_SPAN_MS = 10 * 60 * 1000; // need >= 10 min of history
const SAMPLE_EVERY_MS = 5 * 60 * 1000;

function keyFor(vault: string, chainId: number): string {
  return `yvault-apy-${chainId}-${vault.toLowerCase()}`;
}

function loadSnapshots(key: string): Snapshot[] {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return [];
    const arr = JSON.parse(raw);
    return Array.isArray(arr) ? arr : [];
  } catch {
    return [];
  }
}

/**
 * Estimates APY from the vault's totalAssets growth over time, using
 * snapshots stored in localStorage. Returns null until enough history
 * exists — the UI then shows a "collecting data" state instead of a
 * fabricated number.
 */
export function useApyEstimate(
  vault: string | undefined,
  chainId: number | undefined
): { apy: number | null; collecting: boolean } {
  const [snapshots, setSnapshots] = useState<Snapshot[]>([]);
  const lastSample = useRef<number>(0);

  const { data: totalAssets } = useReadContract({
    address: vault as `0x${string}` | undefined,
    abi: vaultAbi,
    functionName: "totalAssets",
    chainId,
    query: { enabled: !!vault && !!chainId, refetchInterval: 30_000 },
  });

  useEffect(() => {
    if (!vault || !chainId || totalAssets === undefined) return;
    const key = keyFor(vault, chainId);
    const now = Date.now();
    // Throttle sampling; always keep the very first snapshot.
    const existing = loadSnapshots(key);
    if (existing.length > 0 && now - lastSample.current < SAMPLE_EVERY_MS)
      return;
    lastSample.current = now;
    const next = [...existing, { t: now, assets: (totalAssets as bigint).toString() }].slice(
      -MAX_SNAPSHOTS
    );
    try {
      localStorage.setItem(key, JSON.stringify(next));
    } catch {
      /* storage full/blocked — ignore */
    }
    setSnapshots(next);
  }, [vault, chainId, totalAssets]);

  useEffect(() => {
    if (vault && chainId) setSnapshots(loadSnapshots(keyFor(vault, chainId)));
  }, [vault, chainId]);

  if (snapshots.length < 2) return { apy: null, collecting: true };
  const first = snapshots[0];
  const last = snapshots[snapshots.length - 1];
  const spanMs = last.t - first.t;
  if (spanMs < MIN_SPAN_MS) return { apy: null, collecting: true };
  const start = BigInt(first.assets);
  const end = BigInt(last.assets);
  if (start === 0n) return { apy: null, collecting: true };
  const growth = Number(end - start) / Number(start);
  const years = spanMs / (365 * 24 * 60 * 60 * 1000);
  return { apy: growth / years, collecting: false };
}
