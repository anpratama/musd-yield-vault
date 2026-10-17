import { MUSD_ADDRESS } from "../lib/config";
import { explorerAddress } from "../lib/chain";

export function NotDeployed() {
  return (
    <div className="card border-amber-300 bg-amber-50">
      <h2 className="text-lg font-semibold text-amber-900">
        Vault not deployed yet
      </h2>
      <p className="mt-2 text-sm text-amber-800">
        The frontend is ready, but no vault deployment was found. Deploy the
        contracts to Mezo testnet first:
      </p>
      <pre className="mt-3 overflow-x-auto rounded-xl bg-slate-900 p-4 text-xs text-slate-100">
        {`cd mezo-musd-vault
forge script script/Deploy.s.sol \\
  --rpc-url https://rpc.test.mezo.org \\
  --private-key $PRIVATE_KEY --broadcast`}
      </pre>
      <p className="mt-3 text-sm text-amber-800">
        Then either set{" "}
        <span className="font-mono">NEXT_PUBLIC_VAULT_ADDRESS</span> (and{" "}
        <span className="font-mono">NEXT_PUBLIC_SP_STRATEGY_ADDRESS</span>) in{" "}
        <span className="font-mono">frontend/.env.local</span>, or make sure{" "}
        <span className="font-mono">deployments-31611.json</span> exists next to
        the repo root — it is picked up automatically on the next dev/build.
      </p>
      <p className="mt-3 text-sm text-amber-800">
        MUSD (testnet):{" "}
        <a
          className="font-mono text-amber-900 underline"
          href={explorerAddress(MUSD_ADDRESS)}
          target="_blank"
          rel="noreferrer"
        >
          {MUSD_ADDRESS}
        </a>
      </p>
    </div>
  );
}
