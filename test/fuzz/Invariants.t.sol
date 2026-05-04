// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployPool} from "script/DeployPool.s.sol";
import {Pool} from "src/Pool.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "src/mocks/ERC20Mock.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployPool deployer;
    HelperConfig config;
    Pool pool;
    Handler handler;

    address[] users;

    address token0;
    address token1;
    address lpToken;

    function setUp() external {
        for (uint256 i = 0; i < 10; i++) {
            users.push(makeAddr(string(abi.encodePacked("user", i))));
        }

        deployer = new DeployPool();
        (pool, config) = deployer.run();
        handler = new Handler(pool, users);

        (token0, token1, lpToken,) = config.activeNetworkConfig();

        targetContract(address(handler));

        // bytes4[] memory selectors = new bytes4[](3);
        // selectors[0] = Handler.addLiquidity.selector;
        // targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_TotalReservesShareMatchsTokenReserveBalances() public view { //OK
        uint256 totalLP = pool.getTotalLP();
        if(totalLP == 0) return;

        (uint256 reserve0, uint256 reserve1) = pool.getReservePairs();
        if(reserve0 == 0 || reserve1 == 0) return;

        uint256 totalLPUsersToken;
        for (uint256 i = 0; i < users.length; i++) {
            totalLPUsersToken += pool.getUserLP(users[i]);
        }

        uint256 totalReserve0Share = totalLPUsersToken * reserve0 / totalLP;
        uint256 totalReserve1Share = totalLPUsersToken * reserve1 / totalLP;

        assertEq(ERC20Mock(token0).balanceOf(address(pool)), totalReserve0Share, "LP Share token0 Breaks!!");
        assertEq(ERC20Mock(token1).balanceOf(address(pool)), totalReserve1Share, "LP Share token1 Breaks!!");
    }

    function invariant_PoolAndTokenConservation() public view {
        (uint256 reserve0, uint256 reserve1) = pool.getReservePairs();

        assertEq(ERC20Mock(token0).balanceOf(address(pool)), reserve0, "reserves0 and token0 does not match!");
        assertEq(ERC20Mock(token1).balanceOf(address(pool)), reserve1, "reserves1 and token1 does not match!");
    }

    function invariant_LPConservation() public view {
        uint256 sum;

        for (uint256 i = 0; i < users.length; i++) {
            sum += pool.getUserLP(users[i]);
        }

        assertEq(sum, pool.getTotalLP(), "LP Conservation failed");
    }

    function invariant_CanNotClaimMoreThanPool() public view { //OK
        uint256 totalLP = pool.getTotalLP();
        if(totalLP == 0) return;

        (uint256 reserve0, uint256 reserve1) = pool.getReservePairs();
        if(reserve0 == 0 || reserve1 == 0) return;

        uint256 expected0ToRetrieve;
        uint256 expected1ToRetrieve;

        for(uint256 i = 0; i < users.length; i++) {
            uint256 userLP = pool.getUserLP(users[i]);
            if(userLP == 0) continue;

            expected0ToRetrieve += (userLP * reserve0) / totalLP;
            expected1ToRetrieve += (userLP * reserve1) / totalLP;
        }

        assertLe(expected0ToRetrieve, reserve0, "t0 to retrieve greater than reserve 0");
        assertLe(expected1ToRetrieve, reserve1, "t1 to retrieve greater than reserve 1");
    }
}
