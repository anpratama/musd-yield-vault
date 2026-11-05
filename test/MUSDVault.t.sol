// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MUSDVault} from "../src/MUSDVault.sol";
import {MockYieldStrategy} from "../src/MockYieldStrategy.sol";
import {MockMUSD} from "./mocks/MockMUSD.sol";

contract MUSDVaultTest is Test {
    MockMUSD internal musd;
    MUSDVault internal vault;
    MockYieldStrategy internal s1;
    MockYieldStrategy internal s2;

    address internal owner = address(this);
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");

    uint256 internal constant ONE = 1e18;

    function setUp() public {
        musd = new MockMUSD();
        vault = new MUSDVault(
            IERC20(address(musd)),
            owner,
            "Mezo MUSD Yield Vault",
            "yvMUSD",
            address(0) // no BTC feed in unit tests: held BTC valued at 0
        );
        // 10% and 5% simulated APY
        s1 = new MockYieldStrategy(IERC20(address(musd)), address(vault), 1000);
        s2 = new MockYieldStrategy(IERC20(address(musd)), address(vault), 500);
        vault.addStrategy(address(s1), 6000, type(uint256).max); // 60%
        vault.addStrategy(address(s2), 4000, type(uint256).max); // 40%

        musd.mint(user1, 10_000 * ONE);
        musd.mint(user2, 10_000 * ONE);
    }

    // ------------------------------------------------------------------
    // ERC-4626 basics
    // ------------------------------------------------------------------

    function test_DepositWithdrawRedeem() public {
        vm.startPrank(user1);
        musd.approve(address(vault), 2_000 * ONE);

        uint256 shares = vault.deposit(1_000 * ONE, user1);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(user1), shares);

        // Partial withdraw: shares decrease, MUSD returns.
        uint256 musdBefore = musd.balanceOf(user1);
        vault.withdraw(400 * ONE, user1, user1);
        assertEq(musd.balanceOf(user1) - musdBefore, 400 * ONE);
        assertLt(vault.balanceOf(user1), shares);

        // Redeem everything.
        uint256 remaining = vault.balanceOf(user1);
        vault.redeem(remaining, user1, user1);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.totalAssets(), 0);
        vm.stopPrank();
    }

    function test_Mint() public {
        vm.startPrank(user1);
        musd.approve(address(vault), 5_000 * ONE);
        uint256 assetsNeeded = vault.mint(500 * ONE, user1);
        assertEq(vault.balanceOf(user1), 500 * ONE);
        assertLe(assetsNeeded, 500 * ONE + 1); // 1:1 at inception, rounding
        vm.stopPrank();
    }

    function test_SharePriceGrowsWithYield() public {
        // Fund rewards so the mock strategies actually pay yield.
        musd.mint(address(this), 1_000 * ONE);
        musd.approve(address(s1), 1_000 * ONE);
        s1.fundRewards(500 * ONE);
        musd.approve(address(s2), 1_000 * ONE);
        s2.fundRewards(500 * ONE);

        vm.startPrank(user1);
        musd.approve(address(vault), 2_000 * ONE);
        uint256 shares = vault.deposit(2_000 * ONE, user1);
        vm.stopPrank();

        vault.rebalance();
        skip(30 days);
        vault.harvest();

        // Share price (assets per share) must have grown.
        uint256 priceAfter = vault.convertToAssets(ONE);
        assertGt(priceAfter, ONE);
        // And the original depositor can redeem more than deposited.
        vm.prank(user1);
        uint256 out = vault.redeem(shares, user1, user1);
        assertGt(out, 2_000 * ONE);
    }

    // ------------------------------------------------------------------
    // Rebalance
    // ------------------------------------------------------------------

    function test_RebalanceTwoStrategies() public {
        vm.startPrank(user1);
        musd.approve(address(vault), 2_000 * ONE);
        vault.deposit(2_000 * ONE, user1);
        vm.stopPrank();

        vault.rebalance();

        // 60/40 of 2000 -> 1200 / 800
        assertEq(s1.totalAssets(), 1_200 * ONE);
        assertEq(s2.totalAssets(), 800 * ONE);
        assertEq(musd.balanceOf(address(vault)), 0);
    }

    function test_RebalanceIsIdempotent() public {
        vm.startPrank(user1);
        musd.approve(address(vault), 2_000 * ONE);
        vault.deposit(2_000 * ONE, user1);
        vm.stopPrank();

        vault.rebalance();
        uint256 s1After = s1.totalAssets();
        uint256 s2After = s2.totalAssets();
        vault.rebalance();
        assertEq(s1.totalAssets(), s1After);
        assertEq(s2.totalAssets(), s2After);
    }

    function test_RebalanceAfterAllocationChange() public {
        vm.startPrank(user1);
        musd.approve(address(vault), 2_000 * ONE);
        vault.deposit(2_000 * ONE, user1);
        vm.stopPrank();
        vault.rebalance();

        vault.setAllocation(address(s2), 0);
        vault.setAllocation(address(s1), 10_000);
        vault.rebalance();

        assertEq(s1.totalAssets(), 2_000 * ONE);
        assertEq(s2.totalAssets(), 0);
    }

    function test_CapEnforcement() public {
        vault.setCap(address(s1), 500 * ONE);

        vm.startPrank(user1);
        musd.approve(address(vault), 2_000 * ONE);
        vault.deposit(2_000 * ONE, user1);
        vm.stopPrank();
        vault.rebalance();

        // s1 desired = min(2000*60%, 500) = 500; rest flows to s2/idle.
        assertLe(s1.totalAssets(), 500 * ONE);
        assertEq(s2.totalAssets(), 800 * ONE); // 2000 * 40%, under its cap
        assertEq(musd.balanceOf(address(vault)), 700 * ONE); // leftover idle
    }

    // ------------------------------------------------------------------
    // Harvest & compound
    // ------------------------------------------------------------------

    function test_HarvestCompounds() public {
        musd.mint(address(this), 1_000 * ONE);
        musd.approve(address(s1), 1_000 * ONE);
        s1.fundRewards(200 * ONE);

        vm.startPrank(user1);
        musd.approve(address(vault), 2_000 * ONE);
        vault.deposit(2_000 * ONE, user1);
        vm.stopPrank();
        vault.rebalance();
        assertEq(musd.balanceOf(address(vault)), 0);

        skip(30 days);
        // Yield accrues in the strategies' accounting, so TVL has grown.
        uint256 totalBefore = vault.totalAssets();
        assertGt(totalBefore, 2_000 * ONE, "yield must accrue over time");

        vault.harvest();
        uint256 totalAfter = vault.totalAssets();

        // Harvest only moves value (strategy -> vault -> redeployed): conserved.
        assertEq(totalAfter, totalBefore, "harvest must conserve TVL");
        // Claimed MUSD is re-deployed per allocation (60/40): only bps-rounding
        // dust (<= a few wei) may remain idle.
        assertLe(musd.balanceOf(address(vault)), 10);
        assertGt(s1.principal(), 1_200 * ONE, "rewards compounded into principal");
        assertGt(s1.totalAssets(), 1_200 * ONE);
    }

    function test_HarvestWithNoRewardsIsNoop() public {
        vm.startPrank(user1);
        musd.approve(address(vault), 1_000 * ONE);
        vault.deposit(1_000 * ONE, user1);
        vm.stopPrank();
        vault.rebalance();
        vault.harvest(); // no rewards funded -> must not revert
        assertEq(vault.totalAssets(), 1_000 * ONE);
    }

    // ------------------------------------------------------------------
    // Pause / emergency
    // ------------------------------------------------------------------

    function test_PauseBlocksDepositsButNotWithdrawals() public {
        vm.startPrank(user1);
        musd.approve(address(vault), 2_000 * ONE);
        uint256 shares = vault.deposit(1_000 * ONE, user1);
        vm.stopPrank();

        vault.rebalance();
        vault.pause();

        // Deposit blocked while paused.
        vm.startPrank(user1);
        vm.expectRevert();
        vault.deposit(1_000 * ONE, user1);
        // But withdrawal (exit) still works, pulling from strategies.
        uint256 out = vault.redeem(shares, user1, user1);
        vm.stopPrank();
        assertApproxEqAbs(out, 1_000 * ONE, 1);

        vault.unpause();
        vm.startPrank(user1);
        vault.deposit(1_000 * ONE, user1); // works again
        vm.stopPrank();
    }

    function test_EmergencyWithdrawAll() public {
        vm.startPrank(user1);
        musd.approve(address(vault), 2_000 * ONE);
        vault.deposit(2_000 * ONE, user1);
        vm.stopPrank();
        vault.rebalance();
        assertEq(musd.balanceOf(address(vault)), 0);

        vault.pause();
        vault.emergencyWithdrawAll(); // callable while paused

        assertEq(s1.totalAssets(), 0);
        assertEq(s2.totalAssets(), 0);
        assertEq(musd.balanceOf(address(vault)), 2_000 * ONE);
    }

    // ------------------------------------------------------------------
    // Registry admin
    // ------------------------------------------------------------------

    function test_AddStrategyValidation() public {
        MockYieldStrategy s3 = new MockYieldStrategy(
            IERC20(address(musd)),
            address(vault),
            100
        );
        // 6000 + 4000 already used -> any positive bps overflows.
        vm.expectRevert("MUSDVault: bps overflow");
        vault.addStrategy(address(s3), 1, type(uint256).max);

        vm.expectRevert("MUSDVault: zero strategy");
        vault.addStrategy(address(0), 0, type(uint256).max);

        vm.expectRevert("MUSDVault: already added");
        vault.addStrategy(address(s1), 0, type(uint256).max);
    }

    function test_RemoveStrategyRequiresEmpty() public {
        vm.startPrank(user1);
        musd.approve(address(vault), 1_000 * ONE);
        vault.deposit(1_000 * ONE, user1);
        vm.stopPrank();
        vault.rebalance();

        vm.expectRevert("MUSDVault: strategy not empty");
        vault.removeStrategy(address(s1));

        vault.emergencyWithdrawAll();
        vault.removeStrategy(address(s1)); // now empty -> ok
        assertEq(vault.strategyList(0), address(s2));
    }

    function test_SetStrategyActiveExcludesFromAccounting() public {
        vm.startPrank(user1);
        musd.approve(address(vault), 1_000 * ONE);
        vault.deposit(1_000 * ONE, user1);
        vm.stopPrank();
        vault.rebalance();

        vault.setStrategyActive(address(s1), false);
        // Inactive strategy no longer counted in totalAssets.
        assertEq(vault.totalAssets(), s2.totalAssets());
    }

    // ------------------------------------------------------------------
    // Access control
    // ------------------------------------------------------------------

    function test_OnlyOwner() public {
        address attacker = makeAddr("attacker");
        MockYieldStrategy s3 = new MockYieldStrategy(
            IERC20(address(musd)),
            address(vault),
            100
        );

        vm.startPrank(attacker);
        vm.expectRevert();
        vault.addStrategy(address(s3), 0, 0);
        vm.expectRevert();
        vault.setAllocation(address(s1), 0);
        vm.expectRevert();
        vault.setCap(address(s1), 0);
        vm.expectRevert();
        vault.rebalance();
        vm.expectRevert();
        vault.harvest();
        vm.expectRevert();
        vault.pause();
        vm.expectRevert();
        vault.emergencyWithdrawAll();
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    function test_EmitsStrategyAdded() public {
        MockYieldStrategy s3 = new MockYieldStrategy(
            IERC20(address(musd)),
            address(vault),
            100
        );
        // Free up allocation first.
        vault.setAllocation(address(s1), 5000);
        vault.setAllocation(address(s2), 4000);

        vm.expectEmit(true, false, false, true);
        emit MUSDVault.StrategyAdded(address(s3), 1000, 123);
        vault.addStrategy(address(s3), 1000, 123);
    }
}
