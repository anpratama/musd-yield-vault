// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MUSDVault} from "../src/MUSDVault.sol";
import {StabilityPoolStrategy} from "../src/StabilityPoolStrategy.sol";
import {MockYieldStrategy} from "../src/MockYieldStrategy.sol";

/**
 * @notice Deploy MUSDVault + strategies.
 *
 * Env vars (all optional, testnet defaults built in):
 *   MUSD_ADDRESS            MUSD token (default: verified Mezo testnet MUSD)
 *   STABILITY_POOL_ADDRESS  SP adapter target (default: address(0) ->
 *                           strategy auto-resolves the verified testnet SP
 *                           when chain id is 31611)
 *   OWNER_ADDRESS           vault/strategy owner (default: broadcaster)
 *   MOCK_APY_BPS            simulated APY for the mock strategy (default: 800)
 *   BTC_PRICE_FEED          BTC/USD feed used to value BTC gains in
 *                           totalAssets (default: address(0) -> vault and
 *                           strategy auto-resolve Mezo's native price
 *                           precompile when chain id is 31611)
 *   PRIVATE_KEY             deployer key (forge --private-key also works)
 *
 * Example (Mezo testnet):
 *   forge script script/Deploy.s.sol \
 *     --rpc-url https://rpc.test.mezo.org \
 *     --private-key $PRIVATE_KEY --broadcast
 *
 * Deployed addresses are written to ./deployments-<chainid>.json
 */
contract Deploy is Script {
    /// @notice Verified MUSD on Mezo testnet.
    address internal constant TESTNET_MUSD =
        0x118917a40FAF1CD7a13dB0Ef56C86De7973Ac503;

    function run() external {
        address musdAddr = vm.envOr("MUSD_ADDRESS", TESTNET_MUSD);
        address spAddr = vm.envOr("STABILITY_POOL_ADDRESS", address(0));
        address feedAddr = vm.envOr("BTC_PRICE_FEED", address(0));
        uint256 mockApy = vm.envOr("MOCK_APY_BPS", uint256(800)); // 8%

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address owner = vm.envOr("OWNER_ADDRESS", deployer);

        console.log("Deployer :", deployer);
        console.log("Owner    :", owner);
        console.log("MUSD     :", musdAddr);
        console.log("Chain ID :", block.chainid);

        vm.startBroadcast(deployerKey);

        MUSDVault vault = new MUSDVault(
            IERC20(musdAddr),
            owner,
            "Mezo MUSD Yield Vault",
            "yvMUSD",
            feedAddr
        );

        StabilityPoolStrategy spStrategy = new StabilityPoolStrategy(
            musdAddr,
            spAddr,
            address(vault),
            feedAddr
        );

        MockYieldStrategy mockStrategy = new MockYieldStrategy(
            IERC20(musdAddr),
            address(vault),
            mockApy
        );

        // Real yield first; mock simulator registered at 0% as a fallback.
        vault.addStrategy(address(spStrategy), 10_000, type(uint256).max);
        vault.addStrategy(address(mockStrategy), 0, type(uint256).max);

        // Hand strategy ownership to the vault owner as well.
        spStrategy.transferOwnership(owner);
        mockStrategy.transferOwnership(owner);

        vm.stopBroadcast();

        console.log("MUSDVault            :", address(vault));
        console.log("StabilityPoolStrategy:", address(spStrategy));
        console.log("MockYieldStrategy    :", address(mockStrategy));
        console.log("SP resolved to       :", address(spStrategy.stabilityPool()));

        string memory json = "deployments";
        vm.serializeAddress(json, "musd", musdAddr);
        vm.serializeAddress(json, "vault", address(vault));
        vm.serializeAddress(json, "stabilityPoolStrategy", address(spStrategy));
        vm.serializeAddress(json, "stabilityPool", address(spStrategy.stabilityPool()));
        vm.serializeAddress(json, "mockYieldStrategy", address(mockStrategy));
        string memory out = vm.serializeUint(
            json,
            "chainId",
            block.chainid
        );
        string memory path = string.concat(
            "./deployments-",
            vm.toString(block.chainid),
            ".json"
        );
        vm.writeFile(path, out);
        console.log("Wrote", path);
    }
}
