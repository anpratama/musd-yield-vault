# MUSD Auto-Yield Vault

ERC-4626 auto-yield vault for **MUSD** (Mezo's Bitcoin-backed stablecoin),
built for the **Mezo Buildathon (Track 1: DeFi)** on AKINDO.

Users deposit MUSD → receive `yvMUSD` shares → the vault allocates MUSD across
yield strategies (target allocations in bps + per-strategy caps) → yield
auto-compounds → users withdraw anytime. The share token is standard ERC-4626,
so it stays composable with the rest of DeFi (e.g. as lending collateral).

> **Funding state of the Stability Pool adapter — stated honestly:**
> the adapter is **unfunded until deposits actually reach the Stability
> Pool and it earns**. On the current (Wave 1) deployment, the vault holds
> a single idle 500 MUSD deposit and `rebalance()` was never run on-chain,
> so **no MUSD has ever reached the Stability Pool and the adapter has
> earned nothing**. The adapter becomes funded the moment the keeper runs
> `rebalance()` (see `script/keeper.sh`) and `provideToSP` transactions
> move MUSD into the pool. Do not describe it as earning yield before then.

## Contracts (`src/`)

| Contract | Description |
|---|---|
| `MUSDVault.sol` | ERC-4626 vault (OpenZeppelin v5: `ERC4626`, `Ownable`, `Pausable`, `ReentrancyGuard`). Strategy registry with target allocations (bps) and caps, `rebalance()`, `harvest()`, `emergencyWithdrawAll()`, `pause()`/`unpause()`. **No addresses hardcoded** — MUSD is a constructor param. `totalAssets()` also counts native BTC held by the vault (claimed SP gains) at the BTC/USD feed price. |
| `IStrategy.sol` | Strategy interface: `deposit` / `withdraw` / `totalAssets` / `claimRewards`. |
| `StabilityPoolStrategy.sol` | **Real** yield adapter for the MUSD Stability Pool. `deposit()` → `provideToSP`; `withdraw()` → `withdrawFromSP` (pool reverts while gated are caught — see design decisions); `totalAssets()` → compounded deposit **plus the MUSD value of pending BTC liquidation gains** via the BTC/USD feed; `claimRewards()` → `withdrawFromSP(0)` to claim native BTC gains (leaves the deposit untouched) and forwards them to the vault; `claimableGains()` view. The `vault` address is **immutable** (no `setVault` — see Security). SP address is a constructor param, auto-defaulting to the verified Mezo testnet deployment when `block.chainid == 31611`. Interface signatures copied from the official [`mezo-org/musd`](https://github.com/mezo-org/musd) repo — not guessed. |
| `libraries/BtcValuation.sol` | Values native BTC in MUSD via a Chainlink-style BTC/USD feed (`musdValue = btcWei × price / 10^feedDecimals`). Conservative: feed unset/down/stale or non-positive price ⇒ BTC valued at **0**, never a guessed price. On Mezo the feed is the chain's native BTC/USD precompile (`0x7b7c…0015`). |
| `MockYieldStrategy.sol` | **TESTNET SIMULATOR, NOT REAL YIELD.** Linear APY accrual per second, backed by an explicitly funded reward pool (`fundRewards`). Exists so vault rebalance/harvest logic can be demoed end-to-end while the ecosystem matures. |
| `interfaces/IStabilityPool.sol` | Minimal StabilityPool interface vendored from `mezo-org/musd`. |

### Key design decisions

- **Withdrawals always work, even while paused.** `pause()` is an emergency brake on deposits and admin fund movements — never on user exits. `_withdraw` automatically pulls shortfall liquidity from strategies.
- **Caps are enforced on every rebalance** (`desired = min(targetBps share, cap)`).
- **BTC gains are counted, not auto-swapped.** The Stability Pool pays liquidation gains in native BTC. Since Wave 2 those gains are valued in MUSD via the BTC/USD price feed and counted in `totalAssets()` — both while pending in the pool and after harvest, when the vault holds the BTC — so they accrue to share price instead of sitting frozen and uncounted (Wave 1 HIGH finding). They are still not auto-swapped to MUSD: redemptions settle in MUSD and are limited by the vault's actual MUSD liquidity until held BTC is swapped (a DEX-aggregator swap on harvest remains a roadmap item).
- **Protocol-gated withdrawals degrade gracefully.** `withdrawFromSP(amount > 0)` reverts at the MUSD-protocol level while any trove in the system has ICR < MCR, and can also revert on stale oracle prices. Since Wave 2 the strategy catches that revert (emitting `WithdrawalBlocked`) and returns whatever MUSD it already holds (normally 0); the vault measures what each strategy *actually* delivered and continues to the next one. User withdrawals are then fulfilled from idle MUSD / healthy strategies when possible, and only fail — with the vault's own `MUSDVault: insufficient liquidity` error — when total MUSD liquidity genuinely cannot cover them. `rebalance()`, `harvest()` and `emergencyWithdrawAll()` no longer brick on a gated pool, and gains remain claimable throughout via the `withdrawFromSP(0)` path.

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`)

## Install

```bash
cd mezo-musd-vault
forge install   # installs OpenZeppelin v5.0.2 (already pinned in lib/)
cp .env.example .env   # then fill in PRIVATE_KEY
```

## Test

```bash
# Unit tests (no network needed) — must stay green
forge test

# Fork tests against Mezo testnet (needs network; RPC can be flaky -> retry)
forge test --match-contract StabilityPoolForkTest \
  --fork-url https://rpc.test.mezo.org -vvv
```

Fork-test notes:
- The suite auto-skips when not run with a Mezo testnet fork (`vm.skip` on chain id != 31611), so plain `forge test` needs no network.
- Mezo testnet serves the BTC/USD price via a **native chain precompile** (`0x7b7c…0015`) that cannot execute inside a fork. The test `vm.etch`es a mock Chainlink aggregator over it (returning the live price) so the protocol's trove-health check can run. On the real chain no mocking is needed.
- The withdrawal test accepts current protocol state: if testnet troves are under-collateralized, the test asserts the Wave 2 graceful path (the vault surfaces its own `MUSDVault: insufficient liquidity` error and the position stays intact in the pool); otherwise it asserts the full redeem path.

## Deploy (Mezo testnet)

Verified network config — **no placeholders**:

| Item | Value |
|---|---|
| Chain | Mezo testnet |
| Chain ID | `31611` |
| RPC | `https://rpc.test.mezo.org` |
| Explorer | `https://explorer.test.mezo.org` |
| MUSD (testnet) | `0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503` |
| StabilityPool (testnet, proxy) | `0x1CCA7E410eE41739792eA0A24e00349Dd247680e` |
| Faucet | `https://faucet.test.mezo.org` (testnet BTC for gas) |

```bash
# 1. Fund the deployer with testnet BTC from the faucet.
# 2. Get testnet MUSD (borrow against BTC on https://testnet.mezo.org).
# 3. Deploy:
forge script script/Deploy.s.sol \
  --rpc-url https://rpc.test.mezo.org \
  --broadcast
```

Env vars (all optional — testnet defaults are baked in):

| Var | Default | Description |
|---|---|---|
| `PRIVATE_KEY` | — (required) | Deployer key |
| `MUSD_ADDRESS` | `0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503` | MUSD token |
| `STABILITY_POOL_ADDRESS` | `address(0)` → auto-resolves testnet SP on chain 31611 | SP for the strategy |
| `OWNER_ADDRESS` | deployer | Vault/strategy owner (use a multisig in prod) |
| `MOCK_APY_BPS` | `800` | Simulated APY of the mock strategy |

Deployed addresses are written to `./deployments-<chainid>.json`.

Post-deploy demo flow (keeper = owner for the hackathon):
1. `vault.deposit(musdAmount, you)` (after `musd.approve`)
2. `vault.rebalance()` → funds flow into the Stability Pool per allocation
3. `vault.harvest()` → claims BTC gains / mock rewards, compounds MUSD
4. `vault.withdraw(...)` / `vault.redeem(...)` anytime — pulls from strategies automatically

## Security scope (stated honestly for the judges)

- `ReentrancyGuard` on all fund-moving admin functions, `SafeERC20` everywhere, owner-only admin, per-strategy caps, pause that never traps user funds.
- **Strategy `vault` addresses are immutable** (Wave 2 fix). Wave 1's owner-only `setVault` let the owner repoint a strategy at an arbitrary address and drain its position through the vault-only functions (Wave 1 HIGH finding). The setter is removed from both strategies; the vault is fixed at construction and funds can only ever flow back to it.
- Strategies are **trusted, allowlisted** contracts — only register adapters you have reviewed (a malicious strategy could misreport `totalAssets()`).
- **No formal audit** (hackathon scope). First-depositor inflation uses OpenZeppelin defaults — a production deployment should add virtual shares/assets or a minimum initial deposit.

## What changed in Wave 2 (per Wave 1 judge feedback)

1. **HIGH — BTC gains frozen / uncounted:** Stability Pool BTC gains are now valued via the chain's BTC/USD price feed (`libraries/BtcValuation.sol`) and counted in `totalAssets()` at both the strategy level (pending gains) and the vault level (claimed BTC held natively). Feed down/stale ⇒ valued at 0, never guessed. Proven by `test/Wave2Fixes.t.sol::test_BtcGainsIncreaseVaultTotalAssets` (0.05 BTC of gains at $100k ⇒ TVL 10,000 → 15,000 MUSD, before and after harvest).
2. **HIGH — owner could redirect SP funds via `setVault`:** `vault` is now `immutable` on `StabilityPoolStrategy` (and `MockYieldStrategy`); the setter is gone. Proven by `test_VaultCannotBeRedirected`: even after ownership is transferred to an attacker, the vault pointer cannot change and no funds can be pulled.
3. **Withdrawal resilience:** SP withdrawal/claim reverts (110% ICR gate, stale oracle) are caught in the strategy; the vault credits only MUSD actually delivered per strategy and falls back to idle/healthy strategies. Proven by `test_WithdrawalsDegradeGracefullyWhileSpBlocked` and `test_EmergencyWithdrawAllWhileSpBlocked`.
4. **Keeper for on-chain SP activity (L4):** `script/keeper.sh` + `script/Keeper.s.sol` run `rebalance()`/`harvest()` with the owner key read from the `PRIVATE_KEY` env var at run time (never written to disk), producing real `provideToSP`/`withdrawFromSP` transactions from the strategy.
5. **Honest funding wording:** this README and the contract NatSpec now state plainly that the SP adapter is unfunded until `rebalance()` actually moves MUSD into the pool (see the note at the top).

## Roadmap

- Keeper automation (Chainlink Automation / Gelato) for `rebalance()`/`harvest()` — a manual/cron keeper script (`script/keeper.sh`) already ships in Wave 2.
- BTC-gains → MUSD auto-swap on harvest (DEX aggregator).
- Additional real strategies (lending markets / DEX LPs with MUSD) once live.
- Formal audit before any mainnet deployment with meaningful caps.
