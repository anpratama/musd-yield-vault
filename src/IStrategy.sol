// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IStrategy
 * @notice Common interface every yield strategy must implement to be plugged
 * into {MUSDVault}. Strategies hold MUSD (and possibly native-token rewards)
 * and expose a simple deposit/withdraw accounting view.
 */
interface IStrategy {
    /**
     * @notice Pull `amount` MUSD from the caller (the vault) and deploy it
     * into the underlying yield source.
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Withdraw `amount` MUSD from the underlying yield source and send
     * it back to the caller (the vault). If `amount` exceeds the position, the
     * strategy should withdraw as much as possible (never revert on partial
     * liquidity unless the underlying protocol itself reverts).
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Total MUSD value of the strategy's position, including any
     * accrued (not yet claimed) MUSD-denominated yield. Must be cheap and
     * view-only; used by the vault for share pricing.
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Claim any pending rewards from the underlying yield source and
     * forward them to the vault. MUSD rewards are auto-compounded by the
     * vault; non-MUSD rewards (e.g. native BTC gains) are forwarded as-is.
     * Must be a no-op (not a revert) when there is nothing to claim.
     */
    function claimRewards() external;
}
