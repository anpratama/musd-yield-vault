# MUSD Auto-Yield Vault

ERC-4626 auto-yield vault for **MUSD** (Mezo's Bitcoin-backed stablecoin),
built for the **Mezo Buildathon (Track 1: DeFi)** on AKINDO.

Users deposit MUSD → receive `yvMUSD` shares → the vault allocates MUSD across
yield strategies (target allocations in bps + per-strategy caps) → yield
auto-compounds → users withdraw anytime. The share token is standard ERC-4626,
so it stays composable with the rest of DeFi (e.g. as lending collateral).

## Contracts (`src/`)

| Contract | Description |
|---|---|
| `MUSDVault.sol` | ERC-4626 vault (OpenZeppelin v5: `ERC4626`, `Ownable`, `Pausable`, `ReentrancyGuard`). Strategy registry with target allocations (bps) and caps, `rebalance()`, `harvest()`, `emergencyWithdrawAll()`, `pause()`/`unpause()`. **No addresses hardcoded** — MUSD is a constructor param. |
| `IStrategy.sol` | Strategy interface: `deposit` / `withdraw` / `totalAssets` / `claimRewards`. |
| `StabilityPoolStrategy.sol` | **Real** yield adapter for the MUSD Stability Pool. `deposit()` → `provideToSP`; `withdraw()` → `withdrawFromSP`; `totalAssets()` → compounded deposit; `claimRewards()` → `withdrawFromSP(0)` to claim native BTC liquidation gains (leaves the deposit untouched) and forwards them to the vault; `claimableGains()` view. SP address is a constructor param, auto-defaulting to the verified Mezo testnet deployment when `block.chainid == 31611`. Interface signatures copied from the official [`mezo-org/musd`](https://github.com/mezo-org/musd) repo — not guessed. |
| `MockYieldStrategy.sol` | **TESTNET SIMULATOR, NOT REAL YIELD.** Linear APY accrual per second, backed by an explicitly funded reward pool (`fundRewards`). Exists so vault rebalance/harvest logic can be demoed end-to-end while the ecosystem matures. |
| `interfaces/IStabilityPool.sol` | Minimal StabilityPool interface vendored from `mezo-org/musd`. |

### Key design decisions

- **Withdrawals always work, even while paused.** `pause()` is an emergency brake on deposits and admin fund movements — never on user exits. `_withdraw` automatically pulls shortfall liquidity from strategies.
- **Caps are enforced on every rebalance** (`desired = min(targetBps share, cap)`).
- **BTC gains are not auto-swapped.** The Stability Pool pays liquidation gains in native BTC; the vault holds them (visible on-chain) instead of pretending to compound them. Swapping BTC → MUSD (e.g. via a DEX aggregator) is a Wave 2 milestone.
- **Known protocol constraint:** `withdrawFromSP(amount > 0)` reverts at the MUSD-protocol level while any trove in the system has ICR < MCR. The vault surfaces this revert as-is; it is not a vault bug.

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
- The withdrawal test accepts current protocol state: if testnet troves are under-collateralized, the test asserts our stack surfaces the exact protocol revert (`StabilityPool: Cannot withdraw while there are troves with ICR < MCR`); otherwise it asserts the full redeem path.

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
- Strategies are **trusted, allowlisted** contracts — only register adapters you have reviewed (a malicious strategy could misreport `totalAssets()`).
- **No formal audit** (hackathon scope). First-depositor inflation uses OpenZeppelin defaults — a production deployment should add virtual shares/assets or a minimum initial deposit.

## Roadmap (Wave 2)

- Keeper automation (Chainlink Automation / Gelato) for `rebalance()`/`harvest()`.
- BTC-gains → MUSD auto-swap on harvest (DEX aggregator).
- Additional real strategies (lending markets / DEX LPs with MUSD) once live.
- Formal audit before any mainnet deployment with meaningful caps.
