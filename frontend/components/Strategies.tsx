"use client";

import { useStrategies } from "../lib/vault";
import { strategyLabel, type DeploymentInfo } from "../lib/config";
import { fmtBps, fmtMusd } from "../lib/format";
import { AddressLink } from "./ExplorerLink";

export function Strategies({
  vault,
  deployment,
}: {
  vault: string;
  deployment: DeploymentInfo | null;
}) {
  const { rows, loading } = useStrategies(vault);

  return (
    <div className="card">
      <h2 className="text-lg font-semibold">Strategies</h2>
      <p className="mt-1 text-sm text-slate-500">
        Where the vault allocates your MUSD. Allocations are managed by the
        vault keeper via <span className="font-mono">rebalance()</span>.
      </p>
      {loading ? (
        <div className="mt-4 text-sm text-slate-400">Loading strategies…</div>
      ) : rows.length === 0 ? (
        <div className="mt-4 text-sm text-slate-400">
          No strategies registered yet.
        </div>
      ) : (
        <div className="mt-4 overflow-x-auto">
          <table className="w-full min-w-[560px] text-left text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-xs uppercase tracking-wide text-slate-400">
                <th className="pb-2 pr-4 font-medium">Strategy</th>
                <th className="pb-2 pr-4 font-medium">Status</th>
                <th className="pb-2 pr-4 font-medium">Target</th>
                <th className="pb-2 pr-4 font-medium">Deployed</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.address} className="border-b border-slate-100 last:border-0">
                  <td className="py-3 pr-4">
                    <div className="font-medium">
                      {strategyLabel(r.address, deployment)}
                    </div>
                    <AddressLink address={r.address} />
                  </td>
                  <td className="py-3 pr-4">
                    <span
                      className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${
                        r.active
                          ? "bg-emerald-100 text-emerald-700"
                          : "bg-slate-100 text-slate-500"
                      }`}
                    >
                      {r.active ? "Active" : "Inactive"}
                    </span>
                  </td>
                  <td className="py-3 pr-4 font-medium">{fmtBps(r.targetBps)}</td>
                  <td className="py-3 pr-4 font-medium">
                    {fmtMusd(r.assets)} MUSD
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
