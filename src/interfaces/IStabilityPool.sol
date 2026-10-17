// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Minimal interface of the MUSD StabilityPool.
 *
 * Copied from the official mezo-org/musd repository:
 *   solidity/contracts/interfaces/IStabilityPool.sol
 *
 * Signatures and NatSpec below are NOT guessed — they match the deployed
 * contract. Only the functions used by {StabilityPoolStrategy} are included.
 */
interface IStabilityPool {
    /*
     * Initial checks:
     * - _amount is not zero
     * ---
     * - Sends depositor's accumulated gains (collateral) to depositor
     */
    function provideToSP(uint256 _amount) external;

    /*
     * Initial checks:
     * - _amount is zero or there are no under collateralized troves left in the system
     * - User has a non zero deposit
     * ---
     * - Sends all depositor's accumulated gains (collateral) to depositor
     * - Decreases deposit stake, and takes new snapshot.
     *
     * If _amount > userDeposit, the user withdraws all of their compounded deposit.
     */
    function withdrawFromSP(uint256 _amount) external;

    /*
     * Calculates the collateral gain earned by the deposit since its last snapshots were taken.
     */
    function getDepositorCollateralGain(
        address _depositor
    ) external view returns (uint256);

    /*
     * Return the user's compounded deposit.
     */
    function getCompoundedMUSDDeposit(
        address _depositor
    ) external view returns (uint256);
}
