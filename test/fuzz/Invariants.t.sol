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

    address USER = makeAddr("user");
    uint256 TOKEN_INITIAL_AMOUNT = 10000 ether;

    uint256 initialT0 = 1000e18;
    uint256 initialT1 = 100e6;
    uint256 Kinitial;

    function setUp() external {
        for (uint256 i = 0; i < 10; i++) {
            users.push(makeAddr(string(abi.encodePacked("user", i))));
        }

        deployer = new DeployPool();
        (pool, config) = deployer.run();
        handler = new Handler(pool, users);

        //targetContract(address(handler));

        (token0, token1,) = config.activeNetworkConfig();
        USER = users[0];
        ERC20Mock(token0).mint(USER, TOKEN_INITIAL_AMOUNT);
        ERC20Mock(token1).mint(USER, TOKEN_INITIAL_AMOUNT);

        vm.startPrank(USER);
        ERC20Mock(token0).approve(address(pool), initialT0);
        ERC20Mock(token1).approve(address(pool), initialT1);
        //pool.addLiquidity(initialT0, initialT1);

        //(uint256 initialReserve0, uint256 initialReserve1) = pool.getReservePairs();
        //Kinitial = initialReserve0 * initialReserve1;
        vm.stopPrank();

        for (uint256 i = 0; i < users.length; i++) {
            //  console.log("Usuarios en el invariant: ", users[i]);
        }

        targetContract(address(handler));
        console.log("Direccion Invariant: ", address(this));

        // bytes4[] memory selectors = new bytes4[](3);
        // selectors[0] = Handler.addLiquidity.selector;
        // targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_poolRatio() public view {
        (uint256 currentReserve0, uint256 currentReserve1) = pool.getReservePairs();

        if (currentReserve0 == 0 || currentReserve1 == 0) return;

        uint256 k = currentReserve0 * currentReserve1;

        console.log("K BEFORE", Kinitial);
        console.log("K AFTER", k);

        assert(k >= Kinitial);
    }

    function invariant_CacaLPShare_p() public view {
        // uint256 totalLPUsersToken;
        // for (uint256 i = 0; i < users.length; i++) {
        //     totalLPUsersToken += pool.getUserLP(users[i]);
        // }

        // (uint256 reserve0, uint256 reserve1) = pool.getReservePairs();
        // uint256 totalLPTokens = pool.getTotalLP();
        // uint256 totalReserve0Share = totalLPUsersToken * reserve0 / totalLPTokens;
        // uint256 totalReserve1Share = totalLPUsersToken * reserve1 / totalLPTokens;

        // assertEq(ERC20Mock(token0).balanceOf(address(pool)), totalReserve0Share, "LP Share token0 Breaks!!");
        // assertEq(ERC20Mock(token1).balanceOf(address(pool)), totalReserve1Share, "LP Share token1 Breaks!!");
        //assertEq(totalToken0UsersBalances, totalReserve0Share, "LP Share token0 Breaks!!");
        // assertApproxEqRel(
        //     ERC20Mock(token0).balanceOf(address(pool)),
        //     totalReserve0Share,
        //     1e10, // 0.0001% por ejemplo
        //     "LP Share token0 breaks"
        // );

        // assertApproxEqRel(
        //     ERC20Mock(token1).balanceOf(address(pool)),
        //     totalReserve1Share,
        //     1e10, // 0.0001% por ejemplo
        //     "LP Share token0 breaks"
        // );

        // assertApproxEqAbs(ERC20Mock(token0).balanceOf(address(pool)), reserve0, 1e3);
    }

    function invariant_PoolAndTokenConservation() public view {
        (uint256 reserve0, uint256 reserve1) = pool.getReservePairs();

        assertEq(ERC20Mock(token0).balanceOf(address(pool)), reserve0, "LP Share token0 Breaks!!");
        assertEq(ERC20Mock(token1).balanceOf(address(pool)), reserve1, "LP Share token1 Breaks!!");
    }

    function invariant_LPConservation() public view {
        uint256 sum;

        for (uint256 i = 0; i < users.length; i++) {
            sum += pool.getUserLP(users[i]);
        }

        console.log("totalLP", pool.getTotalLP());
        console.log("users sum", sum);
        assertEq(sum, pool.getTotalLP(), "LP Conservation failed");
    }

    function invariant_LPShare() public view {
        uint256 totalLP = pool.getTotalLP();

        if(totalLP == 0) return;

        (uint256 reserve0, uint256 reserve1) = pool.getReservePairs();

        if(reserve0 == 0 || reserve1 == 0) return;

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            uint256 userLP = pool.getUserLP(user);
            uint256 expectedShareLP = userLP / totalLP;
            (uint256 actual0, uint256 actual1) = pool.getUserReservesToRemove(user);
            uint256 expectedShareToken0 = actual0 / reserve0;
            uint256 expectedShareToken1 = actual1 / reserve1;


            console.log("UserLP", userLP);
            //assertEq(expectedShareLP, expectedShareToken0, "LP Share token0 Breaks!!");
            assertApproxEqRel(expectedShareLP, expectedShareToken0, 1e12, "LP Share token0 Breaks!!");
            assertApproxEqRel(expectedShareLP, expectedShareToken1, 1e12, "LP Share token1 Breaks!!");
        }
    }

    function invariant_CrossLPShare() public view {
        uint256 totalLP = pool.getTotalLP();
        (uint256 reserve0, uint256 reserve1) = pool.getReservePairs();

        if (totalLP == 0 || reserve0 == 0) return;

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            uint256 userLP = pool.getUserLP(user);

            if (userLP == 0) continue;
           
            (uint256 actual0,) = pool.getUserReservesToRemove(user);

            // 🔥 Mejor comparar cross-multiplication (evita divisiones)
            uint256 lhs = userLP * reserve0;
            uint256 rhs = actual0 * totalLP;
            console.log("UserLP", userLP);
            assertApproxEqRel(lhs, rhs, 1e12, "LP Share token0 Breaks!!");
            //assertEq(lhs, rhs, "LP Share token0 Breaks!!");
        }
    }

    function invariant_conservationOfToken0() public view {
        uint256 total = ERC20Mock(token0).totalSupply();

        uint256 poolBalance = ERC20Mock(token0).balanceOf(address(pool));

        uint256 userSum = 0;
        for (uint256 i = 0; i < users.length; i++) {
            userSum += ERC20Mock(token0).balanceOf(users[i]);
        }

        console.log("TOTAL:", total);
        console.log("POOL:", poolBalance);
        console.log("USERS:", userSum);
        console.log("DIFF:", total - (poolBalance + userSum));

        assertEq(total, poolBalance + userSum, "CONSERVATION OF TOKENS FAILED");
    }

    function invariant_poolReservesMatchBalances() public view {
        (uint256 reserve0, uint256 reserve1) = pool.getReservePairs();

        uint256 balance0 = ERC20Mock(token0).balanceOf(address(pool));
        uint256 balance1 = ERC20Mock(token1).balanceOf(address(pool));

        assertEq(reserve0, balance0, "RESERVE0 != BALANCE0");
        assertEq(reserve1, balance1, "RESERVE1 != BALANCE1");
    }
}
