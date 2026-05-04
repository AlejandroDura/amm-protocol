// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Pool} from "src/Pool.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployPool is Script {
    function run() external returns (Pool, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address t0, address t1, address lpToken, uint256 deployerKey) = config.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        Pool pool = new Pool(t0, t1, lpToken);
        vm.stopBroadcast();

        return (pool, config);
    }
}
