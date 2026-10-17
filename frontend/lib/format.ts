import { formatUnits } from "viem";

export function fmtMusd(value: bigint | undefined, digits = 2): string {
  if (value === undefined) return "—";
  const n = Number(formatUnits(value, 18));
  return n.toLocaleString("en-US", {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

export function fmtShares(value: bigint | undefined, digits = 4): string {
  if (value === undefined) return "—";
  const n = Number(formatUnits(value, 18));
  return n.toLocaleString("en-US", {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
}

/** Share price: MUSD per 1 share. */
export function fmtSharePrice(assetsPerShare: bigint | undefined): string {
  if (assetsPerShare === undefined) return "—";
  const n = Number(formatUnits(assetsPerShare, 18));
  return n.toFixed(4);
}

export function fmtBps(bps: bigint | undefined): string {
  if (bps === undefined) return "—";
  return `${(Number(bps) / 100).toFixed(1)}%`;
}

export function fmtApy(apy: number | null): string {
  if (apy === null || !isFinite(apy)) return "—";
  return `${(apy * 100).toFixed(2)}%`;
}
