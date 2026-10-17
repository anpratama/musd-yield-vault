# MUSD Yield Vault — Frontend

Next.js (App Router) + wagmi v2 + viem + RainbowKit dapp for the MUSD
auto-yield vault (`MUSDVault.sol`, ERC-4626) on **Mezo testnet** (chain ID 31611).

## Run

```bash
cd frontend
npm install
npm run dev      # http://localhost:3000
```

`predev`/`prebuild` automatically sync `../deployments-31611.json`
(Foundry deploy output) into `public/` so the app picks up fresh contract
addresses without env vars. You can also set them explicitly in
`.env.local` (see `.env.example`):

- `NEXT_PUBLIC_VAULT_ADDRESS`
- `NEXT_PUBLIC_SP_STRATEGY_ADDRESS`
- `NEXT_PUBLIC_MOCK_STRATEGY_ADDRESS`
- `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` (optional — injected wallets work without it)

If no vault address is found, the UI shows a "vault not deployed yet" state
instead of crashing.

## Features

- **Overview**: TVL (`totalAssets`), share price (`convertToAssets`), live
  APY estimate (annualized from `totalAssets` growth tracked in localStorage —
  shows "Collecting…" until enough on-chain history exists, never a fake
  number), your position (yvMUSD shares → MUSD value).
- **Strategies**: every registered strategy with status, target allocation
  (bps) and deployed assets.
- **Deposit / Withdraw**: MUSD approve → deposit (shows estimated yvMUSD via
  `previewDeposit`); withdraw by MUSD amount (shows shares burned via
  `previewWithdraw`). MAX buttons, tx status with explorer links.
- Wrong-network banner with one-click switch to Mezo Testnet.
- Explorer links for every contract address.

## Notes

- ABIs in `abis/` are extracted from the Foundry build artifacts
  (`../out/*.sol/*.json`) — re-extract after contract changes.
- APY history lives in the browser's localStorage, keyed per vault+chain.
- Testnet RPC (`https://rpc.test.mezo.org`) can be flaky; reads retry via
  wagmi's refetch intervals.
