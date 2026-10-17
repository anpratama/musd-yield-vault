import { explorerAddress, explorerTx } from "../lib/chain";
import { shortAddress } from "../lib/config";

export function AddressLink({
  address,
  className = "",
}: {
  address: string;
  className?: string;
}) {
  return (
    <a
      href={explorerAddress(address)}
      target="_blank"
      rel="noreferrer"
      className={`font-mono text-mezo-600 hover:text-mezo-700 hover:underline ${className}`}
      title={address}
    >
      {shortAddress(address)}
    </a>
  );
}

export function TxLink({ hash }: { hash: string }) {
  return (
    <a
      href={explorerTx(hash)}
      target="_blank"
      rel="noreferrer"
      className="font-mono text-mezo-600 hover:underline"
    >
      {shortAddress(hash)}
    </a>
  );
}
