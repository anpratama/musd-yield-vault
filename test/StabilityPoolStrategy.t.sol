// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StabilityPoolStrategy} from "../src/StabilityPoolStrategy.sol";
import {MockMUSD} from "./mocks/MockMUSD.sol";
import {MockStabilityPool} from "./mocks/MockStabilityPool.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";

/// @notice Unit tests for {StabilityPoolStrategy} against a fake pool.
/// Fork tests against the real Mezo testnet pool live in StabilityPoolFork.t.sol.
contract StabilityPoolStrategyTest is Test {
    MockMUSD internal musd;
    MockStabilityPool internal pool;
    MockPriceFeed internal feed;
    StabilityPoolStrategy internal strategy;

    address internal vault = makeAddr("vault");
    uint256 internal constant ONE = 1e18;

    function setUp() public {
        musd = new MockMUSD();
        pool = new MockStabilityPool(IERC20(address(musd)));
        // Fund the fake pool with native tokens to pay simulated BTC gains.
        pool.fundGains{value: 10 ether}();
        // BTC/USD feed at $100,000 (MockPriceFeed default).
        feed = new MockPriceFeed();

        strategy = new StabilityPoolStrategy(
            address(musd),
            address(pool),
            vault,
            address(feed)
        );

        musd.mint(vault, 100_000 * ONE);
        vm.prank(vault);
        musd.approve(address(strategy), type(uint256).max);
    }

    function test_ConstructorDefaultsRevertOffTestnet() public {
        // On a non-Mezo chain, omitting the pool address must revert.
        vm.expectRevert("StabilityPoolStrategy: SP address required");
        new StabilityPoolStrategy(address(musd), address(0), vault, address(0));
    }

    function test_ConstructorRejectsZeroVault() public {
        vm.expectRevert("StabilityPoolStrategy: zero vault");
        new StabilityPoolStrategy(
            address(musd),
            address(pool),
            address(0),
            address(feed)
        );
    }

    function test_DepositWithdrawRoundtrip() public {
        vm.prank(vault);
        strategy.deposit(1_000 * ONE);

        assertEq(strategy.totalAssets(), 1_000 * ONE);
        assertEq(pool.getCompoundedMUSDDeposit(address(strategy)), 1_000 * ONE);

        vm.prank(vault);
        strategy.withdraw(1_000 * ONE);

        assertEq(strategy.totalAssets(), 0);
        assertEq(musd.balanceOf(vault), 100_000 * ONE); // all back
    }

    function test_WithdrawMoreThanDepositedTakesAll() public {
        vm.prank(vault);
        strategy.deposit(1_000 * ONE);

        vm.prank(vault);
        strategy.withdraw(999_999 * ONE); // clamped to position

        assertEq(strategy.totalAssets(), 0);
    }

    function test_ClaimRewardsForwardsNativeGains() public {
        vm.prank(vault);
        strategy.deposit(1_000 * ONE);

        // Simulate a liquidation gain accruing to the strategy's deposit.
        pool.simulateGain(address(strategy), 0.001 ether);
        assertEq(strategy.claimableGains(), 0.001 ether);

        uint256 vaultNativeBefore = vault.balance;
        vm.prank(vault);
        strategy.claimRewards();

        // Gains forwarded to the vault; MUSD deposit untouched.
        assertEq(vault.balance - vaultNativeBefore, 0.001 ether);
        assertEq(strategy.claimableGains(), 0);
        assertEq(strategy.totalAssets(), 1_000 * ONE);
    }

    function test_ClaimRewardsWithNoDepositIsNoop() public {
        vm.prank(vault);
        strategy.claimRewards(); // must not revert
        assertEq(vault.balance, 0);
    }

    function test_OnlyVault() public {
        address attacker = makeAddr("attacker");

        vm.startPrank(attacker);
        vm.expectRevert("StabilityPoolStrategy: only vault");
        strategy.deposit(1);
        vm.expectRevert("StabilityPoolStrategy: only vault");
        strategy.withdraw(1);
        vm.expectRevert("StabilityPoolStrategy: only vault");
        strategy.claimRewards();
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // Wave 2 fix — HIGH 2: setVault redirect removed (vault is immutable)
    // ------------------------------------------------------------------

    /// @notice The Wave 1 attack: owner repoints the strategy at an attacker
    /// address via setVault, then the attacker drains the SP position
    /// through the onlyVault functions. After the fix there is no setter,
    /// vault() can never change, and even a (hostile) new owner cannot move
    /// funds — only the original vault can call the fund-moving functions.
    function test_VaultCannotBeRedirected() public {
        vm.prank(vault);
        strategy.deposit(1_000 * ONE);

        address attacker = makeAddr("attacker");
        // Hand ownership to the attacker: worst case for the old design.
        strategy.transferOwnership(attacker);

        // The vault pointer is unchanged...
        assertEq(strategy.vault(), vault);

        // ...and the attacker still cannot pull any funds out.
        vm.startPrank(attacker);
        vm.expectRevert("StabilityPoolStrategy: only vault");
        strategy.withdraw(1_000 * ONE);
        vm.expectRevert("StabilityPoolStrategy: only vault");
        strategy.claimRewards();
        vm.stopPrank();

        // Position intact and withdrawable by the real vault only.
        assertEq(strategy.totalAssets(), 1_000 * ONE);
        vm.prank(vault);
        strategy.withdraw(1_000 * ONE);
        assertEq(musd.balanceOf(vault), 100_000 * ONE);
        assertEq(musd.balanceOf(attacker), 0);
    }

    // ------------------------------------------------------------------
    // Wave 2 fix — HIGH 1: BTC gains counted in totalAssets
    // ------------------------------------------------------------------

    /// @notice Pending BTC gains must raise totalAssets at the feed price:
    /// 0.01 BTC at $100,000 = 1,000 MUSD on top of the 1,000 MUSD deposit.
    function test_TotalAssetsIncludesBtcGainsValue() public {
        vm.prank(vault);
        strategy.deposit(1_000 * ONE);
        assertEq(strategy.totalAssets(), 1_000 * ONE);

        pool.simulateGain(address(strategy), 0.01 ether);
        assertEq(strategy.totalAssets(), 2_000 * ONE);
    }

    /// @notice A broken feed must value gains at 0 (conservative) and must
    /// NOT revert totalAssets — deposits/withdrawals keep working.
    function test_TotalAssetsWithBrokenFeedValuesGainsAtZero() public {
        vm.prank(vault);
        strategy.deposit(1_000 * ONE);
        pool.simulateGain(address(strategy), 0.01 ether);

        feed.setBroken(true);
        assertEq(strategy.totalAssets(), 1_000 * ONE);
    }

    /// @notice A stale feed answer is treated the same: gains valued at 0.
    function test_TotalAssetsWithStaleFeedValuesGainsAtZero() public {
        vm.warp(10 days);
        feed.refresh(); // fresh at warp time; we age it manually below
        vm.prank(vault);
        strategy.deposit(1_000 * ONE);
        pool.simulateGain(address(strategy), 0.01 ether);
        assertEq(strategy.totalAssets(), 2_000 * ONE); // fresh: counted

        feed.setUpdatedAt(block.timestamp - 2 days);
        assertEq(strategy.totalAssets(), 1_000 * ONE); // stale: valued at 0
    }

    // ------------------------------------------------------------------
    // Wave 2 fix: withdrawal resilience when the SP is gated (ICR check)
    // ------------------------------------------------------------------

    /// @notice While the pool blocks non-zero withdrawals (troves with
    /// ICR < MCR), strategy.withdraw must NOT revert: it delivers 0, the
    /// position stays intact, and gains can still be claimed via
    /// withdrawFromSP(0). Once unblocked, withdrawals work again.
    function test_WithdrawWhilePoolBlockedDegradesGracefully() public {
        vm.prank(vault);
        strategy.deposit(1_000 * ONE);
        pool.simulateGain(address(strategy), 0.001 ether);
        pool.setWithdrawalsBlocked(true);

        // Withdrawal attempt: no revert, nothing delivered, position kept.
        vm.prank(vault);
        strategy.withdraw(500 * ONE);
        assertEq(pool.getCompoundedMUSDDeposit(address(strategy)), 1_000 * ONE);
        assertEq(musd.balanceOf(vault), 100_000 * ONE - 1_000 * ONE);

        // Gains claim still works while blocked (amount-0 path).
        vm.prank(vault);
        strategy.claimRewards();
        assertEq(vault.balance, 0.001 ether);

        // Unblocked: the same withdrawal now succeeds.
        pool.setWithdrawalsBlocked(false);
        vm.prank(vault);
        strategy.withdraw(500 * ONE);
        assertEq(pool.getCompoundedMUSDDeposit(address(strategy)), 500 * ONE);
    }

    receive() external payable {}
}
