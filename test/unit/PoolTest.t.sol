// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployPool} from "script/DeployPool.s.sol";
import {Pool} from "src/Pool.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "src/mocks/ERC20Mock.sol";
import {LPToken} from "src/tokens/LPToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract PoolTest is Test {
    DeployPool deployer;
    Pool pool;
    HelperConfig config;

    address token0;
    address token1;

    address lpToken;

    address USER = makeAddr("user");
    uint256 TOKEN_INITIAL_AMOUNT = 10000 ether;

    function setUp() public {
        deployer = new DeployPool();
        (pool, config) = deployer.run();

        (token0, token1, lpToken,) = config.activeNetworkConfig();

        ERC20Mock(token0).mint(USER, TOKEN_INITIAL_AMOUNT);
        ERC20Mock(token1).mint(USER, TOKEN_INITIAL_AMOUNT);
    }

    ////////////////
    //Constructor//
    //////////////

    function testConstructorInit() public view {
        (address t0, address t1) = pool.getTokenPairs();
        (uint256 r0, uint256 r1) = pool.getReservePairs();
        address _lpToken = pool.getLPToken();

        assertEq(t0, token0);
        assertEq(t1, token1);
        assertEq(_lpToken, lpToken);
        assertEq(r0, 0);
        assertEq(r1, 0);
    }

    //////////////////
    //Add Liquidity//
    ////////////////

    modifier addLiquidity(uint256 deposit_t0, uint256 deposit_t1) {
        vm.startPrank(USER);
        ERC20Mock(token0).approve(address(pool), deposit_t0);
        ERC20Mock(token1).approve(address(pool), deposit_t1);
        pool.addLiquidity(deposit_t0, deposit_t1);
        vm.stopPrank();

        _;
    }

    function testAddLiquidityWithZeroDeposit() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(Pool.Pool__NewDepositsMustBeGreaterThanZero.selector, 0, 0));
        pool.addLiquidity(0, 0);

        vm.expectRevert(abi.encodeWithSelector(Pool.Pool__NewDepositsMustBeGreaterThanZero.selector, 1000e18, 0));
        pool.addLiquidity(1000e18, 0);

        vm.expectRevert(abi.encodeWithSelector(Pool.Pool__NewDepositsMustBeGreaterThanZero.selector, 0, 1000e18));
        pool.addLiquidity(0, 1000e18);
        vm.stopPrank();
    }

    function testAddLiquidity_Once() public {
        uint256 deposit_t0 = 2000e18;
        uint256 deposit_t1 = 100e6;

        uint256 prevToken0AmountPool = ERC20Mock(token0).balanceOf(address(pool));
        uint256 prevToken1AmountPool = ERC20Mock(token1).balanceOf(address(pool));

        vm.startPrank(USER);
        ERC20Mock(token0).approve(address(pool), deposit_t0);
        ERC20Mock(token1).approve(address(pool), deposit_t1);
        pool.addLiquidity(deposit_t0, deposit_t1);
        vm.startPrank(USER);

        (uint256 reserve_t0, uint256 reserve_t1) = pool.getReservePairs();
        uint256 currentToken0AmountPool = ERC20Mock(token0).balanceOf(address(pool));
        uint256 currentToken1AmountPool = ERC20Mock(token1).balanceOf(address(pool));

        assertEq(reserve_t0, deposit_t0);
        assertEq(reserve_t1, deposit_t1);

        assertEq(currentToken0AmountPool, prevToken0AmountPool + deposit_t0);
        assertEq(currentToken1AmountPool, prevToken1AmountPool + deposit_t1);
    }

    function testAddLiquidity_Twice() public {
        //FIRST
        uint256 deposit_t0 = 2000e18;
        uint256 deposit_t1 = 100e6;

        uint256 expectedUserLP = Math.sqrt(deposit_t0 * deposit_t1);
        uint256 expectedTotalLP = expectedUserLP;

        uint256 expectedReserve0 = deposit_t0;
        uint256 expectedReserve1 = deposit_t1;

        uint256 prevToken0AmountPool = ERC20Mock(token0).balanceOf(address(pool));
        uint256 prevToken1AmountPool = ERC20Mock(token1).balanceOf(address(pool));

        vm.startPrank(USER);
        ERC20Mock(token0).approve(address(pool), deposit_t0);
        ERC20Mock(token1).approve(address(pool), deposit_t1);
        pool.addLiquidity(deposit_t0, deposit_t1);
        vm.stopPrank();

        //SECOND
        deposit_t0 = 4000e18;
        deposit_t1 = 250e6;

        uint256 lpMint = Math.min(
            (deposit_t0 * expectedTotalLP) / expectedReserve0, (deposit_t1 * expectedTotalLP) / expectedReserve1
        );

        uint256 t0Used = (lpMint * expectedReserve0) / expectedTotalLP;
        uint256 t1Used = (lpMint * expectedReserve1) / expectedTotalLP;

        expectedReserve0 += t0Used;
        expectedReserve1 += t1Used;

        vm.startPrank(USER);
        ERC20Mock(token0).approve(address(pool), deposit_t0);
        ERC20Mock(token1).approve(address(pool), deposit_t1);
        pool.addLiquidity(deposit_t0, deposit_t1);
        vm.stopPrank();

        (uint256 currentReserve0, uint256 currentReserve1) = pool.getReservePairs();
        uint256 currentToken0AmountPool = ERC20Mock(token0).balanceOf(address(pool));
        uint256 currentToken1AmountPool = ERC20Mock(token1).balanceOf(address(pool));

        assertEq(currentReserve0, expectedReserve0);
        assertEq(currentReserve1, expectedReserve1);

        assertEq(currentToken0AmountPool, prevToken0AmountPool + expectedReserve0);
        assertEq(currentToken1AmountPool, prevToken1AmountPool + expectedReserve1);
    }

    function testMintLP_Once() public {
        uint256 t0Deposit = 2000e18;
        uint256 t1Deposit = 200e6;

        uint256 expectedUserLP = Math.sqrt(t0Deposit * t1Deposit);
        uint256 expectedTotalLP = expectedUserLP;
        vm.startPrank(USER);
        pool.mintLP(t0Deposit, t1Deposit);
        uint256 totalLP = pool.getTotalLP();
        uint256 userLP = pool.getUserLP();
        vm.stopPrank();

        //632.455532033675866399
        //632.455532033675
        console.log("TOTAL LP: ", totalLP);
        console.log("USER LP: ", userLP);
        assertEq(totalLP, expectedTotalLP);
        assertEq(userLP, expectedUserLP);
    }

    function testMintLP_Twice() public {
        //FIRST DEPOSIT
        uint256 t0Deposit = 2000e18;
        uint256 t1Deposit = 200e6;

        uint256 expectedUserLP = Math.sqrt(t0Deposit * t1Deposit);
        uint256 expectedTotalLP = expectedUserLP;

        vm.startPrank(USER);
        pool.mintLP(t0Deposit, t1Deposit);
        vm.stopPrank();

        pool.setFakeReserves(t0Deposit, t1Deposit);

        //SECOND DEPOSIT
        t0Deposit = 4000e18;
        t1Deposit = 300e6;

        (uint256 reserve0, uint256 reserve1) = pool.getReservePairs();

        uint256 lpMint = Math.min((t0Deposit * expectedTotalLP) / reserve0, (t1Deposit * expectedTotalLP) / reserve1);

        uint256 expectedT0Used = (lpMint * reserve0) / expectedTotalLP;
        uint256 expectedT1Used = (lpMint * reserve1) / expectedTotalLP;

        expectedTotalLP += lpMint;
        expectedUserLP += lpMint;

        vm.startPrank(USER);
        (uint256 t0Used, uint256 t1Used) = pool.mintLP(t0Deposit, t1Deposit);
        uint256 currentTotalLP = pool.getTotalLP();
        uint256 currentUserLP = pool.getUserLP();
        vm.stopPrank();
        //1581.138830084187
        //1581.138830084187
        console.log("TOTAL LP: ", currentTotalLP);
        console.log("USER LP: ", currentUserLP);
        assertEq(currentTotalLP, expectedTotalLP, "Total LP");
        assertEq(currentUserLP, expectedUserLP, "User LP");
        assertEq(t0Used, expectedT0Used);
        assertEq(t1Used, expectedT1Used);
    }

    function test_roundingLPMinted() public {
        address userA = makeAddr("user1");
        address userB = makeAddr("user2");

        // reset state si hace falta

        vm.startPrank(userA);
        ERC20Mock(token0).mint(userA, 100e18);
        ERC20Mock(token1).mint(userA, 100e18);

        ERC20Mock(token0).approve(address(pool), type(uint256).max);
        ERC20Mock(token1).approve(address(pool), type(uint256).max);

        pool.addLiquidity(100e18, 100e18);
        uint256 lpA = pool.getUserLP(userA);
        vm.stopPrank();

        vm.startPrank(userB);
        ERC20Mock(token0).mint(userB, 100e18);
        ERC20Mock(token1).mint(userB, 100e18);
        ERC20Mock(token0).approve(address(pool), type(uint256).max);
        ERC20Mock(token1).approve(address(pool), type(uint256).max);

        for (uint256 i = 0; i < 100; i++) {
            pool.addLiquidity(1e18, 1e18);
        }
        uint256 lpB = pool.getUserLP(userB);
        vm.stopPrank();

        assertEq(lpB, lpA);
    }

    /////////////////////
    //Remove Liquidity//
    ///////////////////

    function testRemoveLiquidityWhenThereIsNotLiquidityInTheSystem() public {
        vm.startPrank(USER);
        vm.expectRevert(Pool.Pool__ThereIsNotLiquidityInTheSystem.selector);
        pool.removeLiquidity(100);
        vm.stopPrank();
    }

    function testRemoveZeroLiquidity() public addLiquidity(2000e18, 200e6) {
        vm.startPrank(USER);
        vm.expectRevert(Pool.Pool__LiquidityToRetrieveMustBeGreaterThanZero.selector);
        pool.removeLiquidity(0);
        vm.stopPrank();
    }

    function testRemoveLiquidityGreatherThanTheUserLiquidity() public addLiquidity(2000e18, 200e6) {
        uint256 userLiquidityPercentageToRetrieve = 101;

        vm.startPrank(USER);
        uint256 userLiquidity = pool.getUserLP();
        uint256 liquidityToRetrieve = (userLiquidity * userLiquidityPercentageToRetrieve) / 100;
        vm.expectRevert(Pool.Pool__ProvidedLiquidityExceedsUserLiquidity.selector);
        pool.removeLiquidity(liquidityToRetrieve);
        vm.stopPrank();
    }

    function testRemoveLiquidity() public addLiquidity(2000e18, 200e6) {
        uint256 userLiquidityPercentageToRetrieve = 100;

        uint256 prevUserToken0Balance = ERC20Mock(token0).balanceOf(USER);
        uint256 prevUserToken1Balance = ERC20Mock(token1).balanceOf(USER);

        vm.startPrank(USER);
        uint256 prevUserLiquidity = pool.getUserLP();
        uint256 liquidityToRetrieve = (prevUserLiquidity * userLiquidityPercentageToRetrieve) / 100;
        uint256 prevTotalLiquidity = pool.getTotalLP();
        (uint256 prevReserve0, uint256 prevReserve1) = pool.getReservePairs();

        uint256 reserve0ToRetrieve = (prevReserve0 * liquidityToRetrieve) / prevTotalLiquidity;
        uint256 reserve1ToRetrieve = (prevReserve1 * liquidityToRetrieve) / prevTotalLiquidity;

        pool.removeLiquidity(liquidityToRetrieve);
        uint256 currentUserLiquidity = pool.getUserLP();
        (uint256 currentReserve0, uint256 currentReserve1) = pool.getReservePairs();
        vm.stopPrank();

        assertEq(currentUserLiquidity, prevUserLiquidity - liquidityToRetrieve);
        assertEq(currentReserve0, prevReserve0 - reserve0ToRetrieve);
        assertEq(currentReserve1, prevReserve1 - reserve1ToRetrieve);
        assertEq(ERC20Mock(token0).balanceOf(USER), prevUserToken0Balance + reserve0ToRetrieve);
        assertEq(ERC20Mock(token1).balanceOf(USER), prevUserToken1Balance + reserve1ToRetrieve);
    }

    /////////
    //Swap//
    ///////

    function testSwapWhenTotalSupplyIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(Pool.Pool__ThereIsNotLiquidityInTheSystem.selector);
        pool.swap(token0, 100e18);
        vm.stopPrank();
    }

    function testSwapZeroAmount() public addLiquidity(100e18, 100e6) {
        vm.startPrank(USER);
        vm.expectRevert(Pool.Pool__TokenAmountMustBeGreaterThanZero.selector);
        pool.swap(token1, 0);
        vm.stopPrank();
    }

    function testSwapTokenThatDoesNotExists() public addLiquidity(100e18, 100e6) {
        vm.startPrank(USER);
        vm.expectRevert(Pool.Pool__ProvidedTokenDoesNotExists.selector);
        pool.swap(address(12345), 100e18);
        vm.stopPrank();
    }

    function testSwap_T0forT1() public addLiquidity(5000e18, 1200e6) {
        uint256 reserve0 = 5000e18;
        uint256 reserve1 = 1200e6;

        uint256 t0_to_swap = 100e18;

        uint256 prevPoolToken0Balance = ERC20Mock(token0).balanceOf(address(pool));
        uint256 prevPoolToken1Balance = ERC20Mock(token1).balanceOf(address(pool));

        uint256 feeT0 = t0_to_swap * (100 - 3) / 100;
        uint256 k = reserve0 * reserve1;
        uint256 expected_rec = (reserve1 * feeT0) / (reserve0 + feeT0);

        uint256 expected_t0 = reserve0 + t0_to_swap;
        uint256 expected_t1 = reserve1 - expected_rec;

        vm.startPrank(USER);
        ERC20Mock(token0).approve(address(pool), t0_to_swap);
        pool.swap(token0, t0_to_swap);
        vm.stopPrank();

        uint256 currentPoolToken0Balance = ERC20Mock(token0).balanceOf(address(pool));
        uint256 currentPoolToken1Balance = ERC20Mock(token1).balanceOf(address(pool));

        (uint256 currentReserve0, uint256 currentReserve1) = pool.getReservePairs();

        assertEq(currentReserve0, expected_t0);
        assertEq(currentReserve1, expected_t1, "YEEE");
        assertEq(currentPoolToken0Balance, prevPoolToken0Balance + t0_to_swap, "TOKEN0");
        assertEq(currentPoolToken1Balance, prevPoolToken1Balance - expected_rec, "TOKEN1");
        assertGt(currentReserve0 * currentReserve1, k);
    }

    function testSwap_T1forT0() public addLiquidity(5000e18, 1200e6) {
        uint256 reserve0 = 5000e18;
        uint256 reserve1 = 1200e6;

        uint256 t1_to_swap = 100e18;

        uint256 prevPoolToken0Balance = ERC20Mock(token0).balanceOf(address(pool));
        uint256 prevPoolToken1Balance = ERC20Mock(token1).balanceOf(address(pool));

        // uint256 feeT1 = (t1_to_swap * 3) / 100;
        //uint256 k = reserve0 * reserve1;
        // uint256 expected_t1 = reserve1 + t1_to_swap;
        // uint256 expected_t0 = k / (expected_t1 - feeT1);

        uint256 feeT1 = t1_to_swap * (100 - 3) / 100;
        uint256 k = reserve0 * reserve1;
        uint256 expected_rec = (reserve0 * feeT1) / (reserve1 + feeT1);

        uint256 expected_t1 = reserve1 + t1_to_swap;
        uint256 expected_t0 = reserve0 - expected_rec;

        vm.startPrank(USER);
        ERC20Mock(token1).approve(address(pool), t1_to_swap);
        pool.swap(token1, t1_to_swap);
        vm.stopPrank();

        uint256 currentPoolToken0Balance = ERC20Mock(token0).balanceOf(address(pool));
        uint256 currentPoolToken1Balance = ERC20Mock(token1).balanceOf(address(pool));

        (uint256 currentReserve0, uint256 currentReserve1) = pool.getReservePairs();

        assertEq(currentReserve0, expected_t0);
        assertEq(currentReserve1, expected_t1);
        assertEq(currentPoolToken1Balance, prevPoolToken1Balance + t1_to_swap, "TOKEN1");
        assertEq(currentPoolToken0Balance, prevPoolToken0Balance - expected_rec, "TOKEN1");
        assertGt(currentReserve0 * currentReserve1, k);
    }

    //////////
    //Maths//
    ////////

    function testPairsDecimals() public view {
        (uint8 decimal0, uint8 decimal1) = pool.getPairsDecimals();

        assertEq(decimal0, 18);
        assertEq(decimal1, 6);
    }

    function testPairsDecimalScale() public view {
        (uint256 scale0, uint256 scale1) = pool.getPairsDecimalScale();

        uint256 expectedScale0 = 1;
        uint256 expectedScale1 = 1e12;

        assertEq(scale0, expectedScale0);
        assertEq(scale1, expectedScale1);
    }
}
