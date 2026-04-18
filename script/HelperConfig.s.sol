// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Pool} from "src/Pool.sol";
import {ERC20Mock} from "src/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address token0;
        address token1;
        uint256 deployerKey;
    }

    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint8 public constant USDC_DECIMALS = 6;
    uint8 public constant ETH_DECIMALS = 18;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
        }
    }

    function getAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.token0 != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        ERC20Mock ethMock = new ERC20Mock("wETH", "wETH", ETH_DECIMALS, msg.sender, 1_000_000 * 1e18);
        ERC20Mock usdcMock = new ERC20Mock("USDC", "USDC", USDC_DECIMALS, msg.sender, 1_000_000 * 1e6);
        vm.stopBroadcast();

        return NetworkConfig({token0: address(ethMock), token1: address(usdcMock), deployerKey: DEFAULT_ANVIL_KEY});
    }

    function getSepoliaConfig() public returns (NetworkConfig memory) {
        return NetworkConfig({
            token0: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            token1: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }
}
