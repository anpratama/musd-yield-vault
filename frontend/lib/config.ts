/**
 * Contract address resolution.
 *
 * Priority: NEXT_PUBLIC_* env vars -> public/deployments-31611.json
 * (synced from the Foundry deploy output by scripts/sync-deployments.mjs)
 * -> undefined (UI shows a "not deployed yet" state instead of crashing).
 */

export const MUSD_ADDRESS =
  (process.env.NEXT_PUBLIC_MUSD_ADDRESS as string | undefined) ||
  "0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503"; // verified Mezo testnet MUSD

export interface DeploymentInfo {
  vault?: string;
  spStrategy?: string;
  mockStrategy?: string;
  stabilityPool?: string;
  chainId?: number;
}

let cached: DeploymentInfo | null | undefined;

export async function loadDeployment(): Promise<DeploymentInfo | null> {
  if (cached !== undefined) return cached;

  const fromEnv: DeploymentInfo = {
    vault: process.env.NEXT_PUBLIC_VAULT_ADDRESS || undefined,
    spStrategy: process.env.NEXT_PUBLIC_SP_STRATEGY_ADDRESS || undefined,
    mockStrategy: process.env.NEXT_PUBLIC_MOCK_STRATEGY_ADDRESS || undefined,
  };
  if (fromEnv.vault) {
    cached = fromEnv;
    return cached;
  }

  try {
    const res = await fetch("/deployments-31611.json", { cache: "no-store" });
    if (!res.ok) {
      cached = null;
      return cached;
    }
    const json = await res.json();
    cached = {
      vault: json.vault,
      spStrategy: json.stabilityPoolStrategy,
      mockStrategy: json.mockYieldStrategy,
      stabilityPool: json.stabilityPool,
      chainId: Number(json.chainId),
    };
    return cached;
  } catch {
    cached = null;
    return cached;
  }
}

/** Human-friendly label for a known strategy address. */
export function strategyLabel(
  address: string,
  deployment: DeploymentInfo | null
): string {
  const a = address.toLowerCase();
  if (deployment?.spStrategy && a === deployment.spStrategy.toLowerCase())
    return "Stability Pool Strategy";
  if (deployment?.mockStrategy && a === deployment.mockStrategy.toLowerCase())
    return "Mock Yield Strategy (simulator)";
  return "Strategy";
}

export function shortAddress(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}
