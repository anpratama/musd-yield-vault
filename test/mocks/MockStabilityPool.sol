// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStabilityPool} from "../../src/interfaces/IStabilityPool.sol";

/**
 * @notice Test-only fake of the StabilityPool implementing the vendored
 * {IStabilityPool} interface. Tracks MUSD deposits per depositor and
 * native-token "collateral gains" that accrue via {simulateGain} (as if a
 * liquidation had happened) and are paid out — and cleared — on the next
 * provide/withdraw call, mirroring the real pool's snapshot semantics.
 *
 * {setWithdrawalsBlocked} mirrors the real pool's protocol gate: while
 * blocked, `withdrawFromSP(amount > 0)` reverts with the real pool's
 * ICR error message, while `withdrawFromSP(0)` (gains claim) still works.
 * Used to unit-test {StabilityPoolStrategy} without a fork.
 */
contract MockStabilityPool is IStabilityPool {
    using SafeERC20 for IERC20;

    IERC20 public immutable musd;
    mapping(address => uint256) public deposits;
    /// @notice Accrued, not-yet-paid native collateral gains per depositor.
    mapping(address => uint256) public pendingGains;
    /// @notice When true, non-zero withdrawals revert (ICR gate simulation).
    bool public withdrawalsBlocked;

    constructor(IERC20 _musd) {
        musd = _musd;
    }

    /// @notice Fund this mock with native tokens to pay simulated gains.
    function fundGains() external payable {}

    /// @notice Test helper: accrue `amount` native gains for a depositor,
    /// as if the pool had liquidated an under-collateralized trove.
    function simulateGain(address depositor, uint256 amount) external {
        pendingGains[depositor] += amount;
    }

    /// @notice Test helper: toggle the protocol withdrawal gate.
    function setWithdrawalsBlocked(bool blocked) external {
        withdrawalsBlocked = blocked;
    }

    function provideToSP(uint256 _amount) external override {
        require(_amount > 0, "zero");
        deposits[msg.sender] += _amount;
        musd.safeTransferFrom(msg.sender, address(this), _amount);
        _payGain();
    }

    function withdrawFromSP(uint256 _amount) external override {
        require(deposits[msg.sender] > 0, "no deposit");
        if (_amount > 0 && withdrawalsBlocked) {
            revert(
                "StabilityPool: Cannot withdraw while there are troves with ICR < MCR"
            );
        }
        uint256 payout = _amount > deposits[msg.sender]
            ? deposits[msg.sender]
            : _amount;
        deposits[msg.sender] -= payout;
        if (payout > 0) musd.safeTransfer(msg.sender, payout);
        _payGain();
    }

    function getDepositorCollateralGain(
        address _depositor
    ) external view override returns (uint256) {
        return pendingGains[_depositor];
    }

    function getCompoundedMUSDDeposit(
        address _depositor
    ) external view override returns (uint256) {
        return deposits[_depositor];
    }

    function _payGain() internal {
        uint256 gain = pendingGains[msg.sender];
        if (gain == 0) return;
        pendingGains[msg.sender] = 0;
        require(address(this).balance >= gain, "mock pool underfunded");
        (bool ok, ) = msg.sender.call{value: gain}("");
        require(ok, "gain pay failed");
    }

    receive() external payable {}
}
