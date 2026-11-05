// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MUSDVault} from "../src/MUSDVault.sol";

/**
 * @notice Keeper: trigger rebalance() and/or harvest() on the deployed
 * MUSDVault so the Stability Pool strategy produces real on-chain
 * `provideToSP` / `withdrawFromSP` activity (Wave 2 L4 requirement).
 *
 * `rebalance()` moves idle vault MUSD into the Stability Pool per target
 * allocation; `harvest()` claims accrued BTC gains from the pool
 * (withdrawFromSP(0)) and compounds MUSD rewards.
 *
 * Both vault functions are owner-only, so the signing key MUST be the
 * vault owner's key. The key is read from the PRIVATE_KEY environment
 * variable at run time and is never written to disk by this script.
 *
 * Env vars:
 *   PRIVATE_KEY    (required) vault owner's key
 *   VAULT_ADDRESS  (required) vault to operate. Deliberately NO default:
 *                  defaulting to the Wave 1 vault would let a post-redeploy
 *                  keeper run silently operate the OLD vault instead of the
 *                  new Wave 2 vault, producing L4 activity on the wrong
 *                  contract. Pass the new vault address after redeploy.
 *   KEEPER_ACTION  "all" (default) | "rebalance" | "harvest"
 *
 * Run via script/keeper.sh, or directly:
 *   PRIVATE_KEY=... forge script script/Keeper.s.sol \
 *     --rpc-url https://rpc.test.mezo.org --broadcast
 */
contract Keeper is Script {
    // NOTE: no default vault address on purpose. The Wave 1 vault was
    // 0xDbe56d95ecCAc811d0B85C84D15137696bBB2F40; it is NOT used as a
    // fallback, so a keeper run after the Wave 2 redeploy cannot
    // accidentally operate the old vault. VAULT_ADDRESS must be set
    // explicitly (vm.envAddress reverts if it is missing).

    function run() external {
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        string memory action = vm.envOr("KEEPER_ACTION", string("all"));
        uint256 keeperKey = vm.envUint("PRIVATE_KEY");

        MUSDVault vault = MUSDVault(payable(vaultAddr));

        console.log("Vault        :", vaultAddr);
        console.log("Keeper/owner :", vm.addr(keeperKey));
        console.log("Action       :", action);
        console.log("totalAssets before:", vault.totalAssets());

        bool doRebalance = _eq(action, "all") || _eq(action, "rebalance");
        bool doHarvest = _eq(action, "all") || _eq(action, "harvest");
        require(
            doRebalance || doHarvest,
            "Keeper: KEEPER_ACTION must be all|rebalance|harvest"
        );

        vm.startBroadcast(keeperKey);
        if (doRebalance) vault.rebalance();
        if (doHarvest) vault.harvest();
        vm.stopBroadcast();

        console.log("totalAssets after :", vault.totalAssets());
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return
            keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
