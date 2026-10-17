// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StabilityPoolStrategy} from "../src/StabilityPoolStrategy.sol";
import {MockMUSD} from "./mocks/MockMUSD.sol";
import {MockStabilityPool} from "./mocks/MockStabilityPool.sol";

/// @notice Unit tests for {StabilityPoolStrategy} against a fake pool.
/// Fork tests against the real Mezo testnet pool live in StabilityPoolFork.t.sol.
contract StabilityPoolStrategyTest is Test {
    MockMUSD internal musd;
    MockStabilityPool internal pool;
    StabilityPoolStrategy internal strategy;

    address internal vault = makeAddr("vault");
    uint256 internal constant ONE = 1e18;

    function setUp() public {
        musd = new MockMUSD();
        pool = new MockStabilityPool(IERC20(address(musd)));
        // Fund the fake pool with native tokens to pay simulated BTC gains.
        pool.fundGains{value: 10 ether}(0.001 ether);

        strategy = new StabilityPoolStrategy(
            address(musd),
            address(pool),
            vault
        );

        musd.mint(vault, 100_000 * ONE);
        vm.prank(vault);
        musd.approve(address(strategy), type(uint256).max);
    }

    function test_ConstructorDefaultsRevertOffTestnet() public {
        // On a non-Mezo chain, omitting the pool address must revert.
        vm.expectRevert("StabilityPoolStrategy: SP address required");
        new StabilityPoolStrategy(address(musd), address(0), vault);
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

        uint256 gains = strategy.claimableGains();
        assertEq(gains, 0.001 ether);

        uint256 vaultNativeBefore = vault.balance;
        vm.prank(vault);
        strategy.claimRewards();

        // Gains forwarded to the vault; MUSD deposit untouched.
        assertEq(vault.balance - vaultNativeBefore, 0.001 ether);
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

    function test_SetVaultOnlyOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        strategy.setVault(attacker);

        strategy.setVault(makeAddr("vault2"));
        assertEq(strategy.vault(), makeAddr("vault2"));
    }

    receive() external payable {}
}
