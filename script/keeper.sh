#!/usr/bin/env bash
# Keeper runner for the MUSD Yield Vault (Mezo testnet).
#
# Triggers rebalance() and/or harvest() on the deployed vault so the
# Stability Pool strategy generates real on-chain provideToSP /
# withdrawFromSP activity (Wave 2 L4 requirement).
#
# The signing key is read from the PRIVATE_KEY environment variable at run
# time. It is never written to disk, never echoed, and never committed.
# The key must belong to the vault owner (rebalance/harvest are owner-only).
#
# Usage:
#   export PRIVATE_KEY=0x...          # vault owner's key (testnet)
#   export VAULT_ADDRESS=0x...        # REQUIRED: the vault to operate.
#                                      # After the Wave 2 redeploy this MUST be
#                                      # the NEW vault address. There is
#                                      # deliberately NO default: the old
#                                      # default pointed at the Wave 1 vault
#                                      # (0xDbe56d95ecCAc811d0B85C84D15137696bBB2F40),
#                                      # and running the keeper without an
#                                      # explicit address after redeploy would
#                                      # have produced provideToSP activity on
#                                      # the OLD vault instead of the Wave 2 one.
#   ./script/keeper.sh                # rebalance + harvest
#   KEEPER_ACTION=rebalance ./script/keeper.sh
#   KEEPER_ACTION=harvest   ./script/keeper.sh
#
# Optional: RPC_URL (default https://rpc.test.mezo.org).
# Cron example (hourly, key sourced from a local, uncommitted env file):
#   0 * * * *  . ~/.config/musd-vault/keeper.env && /path/to/script/keeper.sh >> /var/log/musd-keeper.log 2>&1
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${PRIVATE_KEY:-}" ]]; then
  echo "ERROR: PRIVATE_KEY is not set in the environment." >&2
  echo "Export the vault owner's key first:  export PRIVATE_KEY=0x..." >&2
  exit 1
fi

if [[ -z "${VAULT_ADDRESS:-}" ]]; then
  echo "ERROR: VAULT_ADDRESS is not set. Refusing to run against any default vault." >&2
  echo "After the Wave 2 redeploy, export the NEW vault address first:" >&2
  echo "  export VAULT_ADDRESS=0x...   # new Wave 2 MUSDVault address" >&2
  echo "The Wave 1 vault (0xDbe56d95ecCAc811d0B85C84D15137696bBB2F40) is deliberately" >&2
  echo "no longer the default, so the keeper cannot silently operate the old vault." >&2
  exit 1
fi

RPC_URL="${RPC_URL:-https://rpc.test.mezo.org}"
export KEEPER_ACTION="${KEEPER_ACTION:-all}"
export VAULT_ADDRESS="${VAULT_ADDRESS}"

echo "Keeper: action=${KEEPER_ACTION} vault=${VAULT_ADDRESS} rpc=${RPC_URL}"

forge script script/Keeper.s.sol \
  --rpc-url "${RPC_URL}" \
  --broadcast

echo "Keeper: done."
