// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStabilityPool} from "../../src/interfaces/IStabilityPool.sol";

/**
 * @notice Test-only fake of the StabilityPool implementing the vendored
 * {IStabilityPool} interface. Tracks MUSD deposits per depositor and pays a
 * fixed native-token "collateral gain" on every provide/withdraw(0) call.
 * Used to unit-test {StabilityPoolStrategy} without a fork.
 */
contract MockStabilityPool is IStabilityPool {
    using SafeERC20 for IERC20;

    IERC20 public immutable musd;
    mapping(address => uint256) public deposits;
    /// @notice Native gain paid out per claim (simulates liquidation gains).
    uint256 public gainPerClaim;

    constructor(IERC20 _musd) {
        musd = _musd;
    }

    /// @notice Fund this mock with native tokens to pay simulated gains.
    function fundGains(uint256 _gainPerClaim) external payable {
        gainPerClaim = _gainPerClaim;
    }

    function provideToSP(uint256 _amount) external override {
        require(_amount > 0, "zero");
        deposits[msg.sender] += _amount;
        musd.safeTransferFrom(msg.sender, address(this), _amount);
        _payGain();
    }

    function withdrawFromSP(uint256 _amount) external override {
        require(deposits[msg.sender] > 0, "no deposit");
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
        return deposits[_depositor] > 0 ? gainPerClaim : 0;
    }

    function getCompoundedMUSDDeposit(
        address _depositor
    ) external view override returns (uint256) {
        return deposits[_depositor];
    }

    function _payGain() internal {
        if (gainPerClaim > 0 && address(this).balance >= gainPerClaim) {
            (bool ok, ) = msg.sender.call{value: gainPerClaim}("");
            require(ok, "gain pay failed");
        }
    }

    receive() external payable {}
}
