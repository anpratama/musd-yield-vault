// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MUSDVault} from "../src/MUSDVault.sol";
import {StabilityPoolStrategy} from "../src/StabilityPoolStrategy.sol";
import {MockYieldStrategy} from "../src/MockYieldStrategy.sol";
import {MockMUSD} from "./mocks/MockMUSD.sol";
import {MockStabilityPool} from "./mocks/MockStabilityPool.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";

/**
 * @notice Wave 2 judge-feedback fixes, proven end-to-end at the vault level:
 *  - HIGH 1: BTC gains from the Stability Pool increase vault totalAssets
 *    (both while pending in the pool and after harvest, when the vault
 *    holds the BTC natively).
 *  - Withdrawal resilience: while the SP gates withdrawals (ICR check),
 *    vault withdrawals are fulfilled from other strategies / idle MUSD
 *    instead of bricking, and harvest/rebalance keep working.
 *
 * MockPriceFeed default price: $100,000 per BTC.
 */
contract Wave2FixesTest is Test {
    MockMUSD internal musd;
    MockStabilityPool internal pool;
    MockPriceFeed internal feed;
    MUSDVault internal vault;
    StabilityPoolStrategy internal spStrategy;
    MockYieldStrategy internal mockStrategy;

    address internal owner = address(this);
    address internal user = makeAddr("user");

    uint256 internal constant ONE = 1e18;

    function setUp() public {
        musd = new MockMUSD();
        pool = new MockStabilityPool(IERC20(address(musd)));
        pool.fundGains{value: 10 ether}();
        feed = new MockPriceFeed(); // $100,000 / BTC

        vault = new MUSDVault(
            IERC20(address(musd)),
            owner,
            "Mezo MUSD Yield Vault",
            "yvMUSD",
            address(feed)
        );
        spStrategy = new StabilityPoolStrategy(
            address(musd),
            address(pool),
            address(vault),
            address(feed)
        );
        mockStrategy = new MockYieldStrategy(
            IERC20(address(musd)),
            address(vault),
            0 // no simulated yield in these tests
        );

        musd.mint(user, 100_000 * ONE);
    }

    function _depositAndRebalance(uint256 amount) internal returns (uint256) {
        vm.startPrank(user);
        musd.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, user);
        vm.stopPrank();
        vault.rebalance();
        return shares;
    }

    // ------------------------------------------------------------------
    // HIGH 1: BTC gains increase totalAssets
    // ------------------------------------------------------------------

    /// @notice Full flow: deposit -> rebalance into the SP -> liquidation
    /// gains accrue -> totalAssets and share price rise BEFORE harvest
    /// (pending gains counted via the strategy) and stay up AFTER harvest
    /// (gains now held by the vault as native BTC, counted via the vault).
    function test_BtcGainsIncreaseVaultTotalAssets() public {
        vault.addStrategy(address(spStrategy), 10_000, type(uint256).max);
        uint256 shares = _depositAndRebalance(10_000 * ONE);

        // All MUSD reached the pool; nothing earned yet.
        assertEq(pool.getCompoundedMUSDDeposit(address(spStrategy)), 10_000 * ONE);
        assertEq(vault.totalAssets(), 10_000 * ONE);
        assertEq(vault.convertToAssets(ONE), ONE);

        // A liquidation pays the SP depositors 0.05 BTC in gains.
        // At $100,000/BTC that is 5,000 MUSD of value.
        pool.simulateGain(address(spStrategy), 0.05 ether);

        // Pending gains are counted: TVL and share price rise pre-harvest.
        // (Approx: OZ ERC4626 virtual-share offset introduces <= wei dust.)
        assertEq(vault.totalAssets(), 15_000 * ONE);
        assertApproxEqAbs(vault.convertToAssets(ONE), (3 * ONE) / 2, 10);

        // Harvest claims the BTC into the vault; TVL must not drop (the
        // value moves from "pending in pool" to "held by vault").
        vault.harvest();
        assertEq(address(vault).balance, 0.05 ether);
        assertEq(spStrategy.claimableGains(), 0);
        assertEq(vault.totalAssets(), 15_000 * ONE);
        assertApproxEqAbs(vault.convertToAssets(ONE), (3 * ONE) / 2, 10);

        // The depositor's shares are worth 15,000 MUSD of accounted value.
        assertApproxEqAbs(vault.convertToAssets(shares), 15_000 * ONE, 10);
    }

    /// @notice With the feed down, gains are valued at 0 — totalAssets
    /// falls back to the MUSD-only figure instead of reverting.
    function test_BtcGainsValuedAtZeroWhenFeedDown() public {
        vault.addStrategy(address(spStrategy), 10_000, type(uint256).max);
        _depositAndRebalance(10_000 * ONE);
        pool.simulateGain(address(spStrategy), 0.05 ether);
        assertEq(vault.totalAssets(), 15_000 * ONE);

        feed.setBroken(true);
        assertEq(vault.totalAssets(), 10_000 * ONE);
    }

    // ------------------------------------------------------------------
    // Withdrawal resilience while the SP is gated
    // ------------------------------------------------------------------

    /// @notice SP holds 50%, mock strategy 50%. The pool blocks non-zero
    /// withdrawals (ICR gate). A withdrawal covered by the healthy
    /// strategy must still succeed; one that needs the blocked SP funds
    /// fails with the vault's own error; harvest and rebalance keep
    /// working throughout; once unblocked, everything is withdrawable.
    function test_WithdrawalsDegradeGracefullyWhileSpBlocked() public {
        vault.addStrategy(address(spStrategy), 5000, type(uint256).max);
        vault.addStrategy(address(mockStrategy), 5000, type(uint256).max);
        uint256 shares = _depositAndRebalance(10_000 * ONE);
        assertEq(spStrategy.totalAssets(), 5_000 * ONE);
        assertEq(mockStrategy.totalAssets(), 5_000 * ONE);

        pool.setWithdrawalsBlocked(true);

        // Withdrawal fully covered by the healthy mock strategy: succeeds
        // even though the SP leg delivers 0.
        vm.prank(user);
        uint256 out = vault.withdraw(4_000 * ONE, user, user);
        assertEq(out, 4_000 * ONE);
        assertEq(musd.balanceOf(user), 100_000 * ONE - 10_000 * ONE + 4_000 * ONE);
        // SP position untouched (still locked in the pool, not lost).
        assertEq(pool.getCompoundedMUSDDeposit(address(spStrategy)), 5_000 * ONE);

        // Harvest still works while blocked: gains are claimable via the
        // amount-0 path and reach the vault.
        pool.simulateGain(address(spStrategy), 0.001 ether);
        vault.harvest();
        assertEq(address(vault).balance, 0.001 ether);

        // Rebalance must not brick on the blocked SP leg either.
        vault.rebalance();

        // A withdrawal that genuinely needs the blocked SP funds fails
        // with the vault's own clear error — not a raw pool revert, and
        // no funds move.
        vm.prank(user);
        vm.expectRevert("MUSDVault: insufficient liquidity");
        vault.withdraw(3_000 * ONE, user, user);

        // Unblock: the remaining MUSD position becomes fully withdrawable.
        pool.setWithdrawalsBlocked(false);
        uint256 userMusdBefore = musd.balanceOf(user);
        vm.prank(user);
        vault.withdraw(6_000 * ONE, user, user);
        assertEq(musd.balanceOf(user) - userMusdBefore, 6_000 * ONE);
        assertEq(pool.getCompoundedMUSDDeposit(address(spStrategy)), 0);
        assertEq(mockStrategy.totalAssets(), 0);
        // What remains is exactly the un-swapped BTC-gain value (100 MUSD):
        // counted in totalAssets, but not MUSD liquidity until swapped.
        assertEq(vault.totalAssets(), 100 * ONE);
        assertGt(vault.balanceOf(user), 0);
    }

    /// @notice emergencyWithdrawAll must not brick while the SP is gated:
    /// it recovers what it can (the healthy strategy) and leaves the
    /// blocked position in place.
    function test_EmergencyWithdrawAllWhileSpBlocked() public {
        vault.addStrategy(address(spStrategy), 5000, type(uint256).max);
        vault.addStrategy(address(mockStrategy), 5000, type(uint256).max);
        _depositAndRebalance(10_000 * ONE);

        pool.setWithdrawalsBlocked(true);
        vault.emergencyWithdrawAll(); // must not revert

        assertEq(mockStrategy.totalAssets(), 0);
        assertEq(musd.balanceOf(address(vault)), 5_000 * ONE);
        assertEq(pool.getCompoundedMUSDDeposit(address(spStrategy)), 5_000 * ONE);
    }

    receive() external payable {}
}
