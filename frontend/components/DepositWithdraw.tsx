"use client";

import { useEffect, useState } from "react";
import type { Abi } from "viem";
import { maxUint256, parseUnits } from "viem";
import {
  useAccount,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import vaultAbiJson from "../abis/vault.json";
import erc20AbiJson from "../abis/erc20.json";
import { mezoTestnet } from "../lib/chain";
import { MUSD_ADDRESS } from "../lib/config";
import { useVaultCore } from "../lib/vault";
import { fmtMusd, fmtShares } from "../lib/format";
import { TxLink } from "./ExplorerLink";

const vaultAbi = vaultAbiJson as Abi;
const erc20Abi = erc20AbiJson as Abi;
const CHAIN_ID = mezoTestnet.id;

function parseAmount(input: string): bigint | null {
  if (!input.trim()) return null;
  try {
    const v = parseUnits(input.trim(), 18);
    return v > 0n ? v : null;
  } catch {
    return null;
  }
}

export function DepositWithdraw({ vault }: { vault: string }) {
  const { address: user } = useAccount();
  const [tab, setTab] = useState<"deposit" | "withdraw">("deposit");
  const [amount, setAmount] = useState("");
  const { paused, refetchAssets } = useVaultCore(vault);

  const v = vault as `0x${string}`;
  const m = MUSD_ADDRESS as `0x${string}`;
  const parsed = parseAmount(amount);

  const { data: musdBalance, refetch: refetchMusd } = useReadContract({
    address: m,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: user ? [user] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: !!user, refetchInterval: 20_000 },
  });
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: m,
    abi: erc20Abi,
    functionName: "allowance",
    args: user ? [user, v] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: !!user, refetchInterval: 20_000 },
  });
  const { data: shareBalance, refetch: refetchShares } = useReadContract({
    address: v,
    abi: vaultAbi,
    functionName: "balanceOf",
    args: user ? [user] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: !!user, refetchInterval: 20_000 },
  });
  const { data: maxWithdraw } = useReadContract({
    address: v,
    abi: vaultAbi,
    functionName: "maxWithdraw",
    args: user ? [user] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: !!user, refetchInterval: 20_000 },
  });
  const { data: previewShares } = useReadContract({
    address: v,
    abi: vaultAbi,
    functionName: "previewDeposit",
    args: parsed ? [parsed] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: tab === "deposit" && parsed !== null },
  });
  const { data: previewBurn } = useReadContract({
    address: v,
    abi: vaultAbi,
    functionName: "previewWithdraw",
    args: parsed ? [parsed] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: tab === "withdraw" && parsed !== null },
  });

  const { writeContract, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: confirming, isSuccess: confirmed } =
    useWaitForTransactionReceipt({ hash: txHash, chainId: CHAIN_ID });

  useEffect(() => {
    if (confirmed) {
      refetchMusd();
      refetchAllowance();
      refetchShares();
      refetchAssets();
    }
  }, [confirmed, refetchMusd, refetchAllowance, refetchShares, refetchAssets]);

  const needsApproval =
    tab === "deposit" &&
    parsed !== null &&
    (allowance as bigint | undefined) !== undefined &&
    (allowance as bigint) < parsed;

  const maxAmount =
    tab === "deposit"
      ? (musdBalance as bigint | undefined)
      : (maxWithdraw as bigint | undefined);

  function handleApprove() {
    if (!parsed || !user) return;
    reset();
    writeContract({
      address: m,
      abi: erc20Abi,
      functionName: "approve",
      args: [v, parsed],
      chainId: CHAIN_ID,
    });
  }

  function handleDeposit() {
    if (!parsed || !user) return;
    reset();
    writeContract({
      address: v,
      abi: vaultAbi,
      functionName: "deposit",
      args: [parsed, user],
      chainId: CHAIN_ID,
    });
  }

  function handleWithdraw() {
    if (!parsed || !user) return;
    reset();
    writeContract({
      address: v,
      abi: vaultAbi,
      functionName: "withdraw",
      args: [parsed, user, user],
      chainId: CHAIN_ID,
    });
  }

  const busy = isPending || confirming;

  return (
    <div className="card">
      <div className="mb-4 grid grid-cols-2 gap-1 rounded-full border border-white/5 bg-white/5 p-1">
        {(["deposit", "withdraw"] as const).map((t) => (
          <button
            key={t}
            onClick={() => {
              setTab(t);
              setAmount("");
              reset();
            }}
            className={`rounded-full py-2 text-sm font-semibold capitalize transition ${
              tab === t ? "bg-zinc-100 text-zinc-900 shadow" : "text-zinc-400 hover:text-zinc-200"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {!user ? (
        <p className="py-6 text-center text-sm text-zinc-400">
          Connect your wallet to {tab}.
        </p>
      ) : (
        <>
          <label className="label" htmlFor="amount">
            Amount (MUSD)
          </label>
          <div className="relative">
            <input
              id="amount"
              className="input pr-16"
              inputMode="decimal"
              placeholder="0.00"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
            <button
              onClick={() =>
                setAmount(
                  maxAmount !== undefined
                    ? (Number(maxAmount) / 1e18).toString()
                    : ""
                )
              }
              className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full border border-white/10 bg-white/5 px-2.5 py-1 text-xs font-bold text-zinc-300 hover:bg-white/10"
            >
              MAX
            </button>
          </div>
          <div className="mt-1.5 flex justify-between text-xs text-zinc-500">
            <span>
              Wallet: {fmtMusd(musdBalance as bigint | undefined)} MUSD
            </span>
            <span>
              Position: {fmtShares(shareBalance as bigint | undefined)} yvMUSD
            </span>
          </div>

          {tab === "deposit" && parsed !== null && (
            <div className="mt-3 rounded-2xl bg-white/5 px-4 py-3 text-sm text-zinc-300">
              You receive ≈{" "}
              <strong>{fmtShares(previewShares as bigint | undefined)} yvMUSD</strong>
            </div>
          )}
          {tab === "withdraw" && parsed !== null && (
            <div className="mt-3 rounded-2xl bg-white/5 px-4 py-3 text-sm text-zinc-300">
              Burns ≈{" "}
              <strong>{fmtShares(previewBurn as bigint | undefined)} yvMUSD</strong>
              , you receive <strong>{fmtMusd(parsed)} MUSD</strong>
            </div>
          )}

          <div className="mt-4 space-y-2">
            {tab === "deposit" ? (
              <>
                {paused ? (
                  <div className="rounded-2xl border border-amber-500/30 bg-amber-500/10 px-4 py-3 text-sm text-amber-200">
                    Deposits are paused. Withdrawals remain open.
                  </div>
                ) : needsApproval ? (
                  <button
                    className="btn-primary w-full"
                    disabled={busy}
                    onClick={handleApprove}
                  >
                    {busy ? "Confirm in wallet…" : `Approve ${fmtMusd(parsed)} MUSD`}
                  </button>
                ) : (
                  <button
                    className="btn-primary w-full"
                    disabled={busy || parsed === null}
                    onClick={handleDeposit}
                  >
                    {busy ? "Confirm in wallet…" : "Deposit"}
                  </button>
                )}
              </>
            ) : (
              <button
                className="btn-primary w-full"
                disabled={busy || parsed === null}
                onClick={handleWithdraw}
              >
                {busy ? "Confirm in wallet…" : "Withdraw"}
              </button>
            )}
          </div>

          {txHash && (
            <div className="mt-3 text-center text-sm text-zinc-400">
              {confirmed ? (
                <span className="font-medium text-emerald-400">
                  Confirmed · <TxLink hash={txHash} />
                </span>
              ) : (
                <span>
                  Submitted · <TxLink hash={txHash} />
                </span>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
}

// Re-export to avoid unused import warnings in some toolchains
export { maxUint256 };
