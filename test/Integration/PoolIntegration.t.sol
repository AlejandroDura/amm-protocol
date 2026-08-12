// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployPool} from "script/DeployPool.s.sol";
import {Pool} from "src/Pool.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "src/mocks/ERC20Mock.sol";
import {LPToken} from "src/tokens/LPToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract PoolIntegration is Test {
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

    modifier addLiquidity(uint256 deposit_t0, uint256 deposit_t1) {
        vm.startPrank(USER);
        ERC20Mock(token0).approve(address(pool), deposit_t0);
        ERC20Mock(token1).approve(address(pool), deposit_t1);
        pool.addLiquidity(deposit_t0, deposit_t1);
        vm.stopPrank();
        _;
    }

    function test_Sell() public addLiquidity(2000e18, 1000e6) {
        uint256 amountToSell = 100e18;
        address tokenToSell = token0;

        uint256 tokenToSellPrevAmount = ERC20Mock(tokenToSell).balanceOf(USER);
        uint256 tokenToBuyPrevAmount = ERC20Mock(_getOtherToken(tokenToSell)).balanceOf(USER);
        uint256 expectedTokenBuyedAmount = _getAmountToBuy(tokenToSell, amountToSell);
        vm.startPrank(USER);
        ERC20Mock(tokenToSell).approve(address(pool), amountToSell);
        pool.swap(tokenToSell, amountToSell, 0);
        vm.stopPrank();

        uint256 tokenToSellCurrentAmount = ERC20Mock(tokenToSell).balanceOf(USER);
        uint256 tokenToBuyCurrentAmount = ERC20Mock(_getOtherToken(tokenToSell)).balanceOf(USER);

        console.log("EXPECTED: ", expectedTokenBuyedAmount);
        assertEq(tokenToSellCurrentAmount, tokenToSellPrevAmount - amountToSell);
        assertEq(tokenToBuyCurrentAmount, tokenToBuyPrevAmount + expectedTokenBuyedAmount);
    }

    function test_Buy() public addLiquidity(5000e18, 8000e6) {
        uint256 amountToBuy = 100e18;
        address tokenToBuy = token0;
        address tokenToSell = _getOtherToken(tokenToBuy);

        uint256 expectedTokenSelledAmount = _getAmountToSell(tokenToBuy, amountToBuy);
        console.log("EXPECTED: ", expectedTokenSelledAmount);

        uint256 tokenToBuyPrevAmount = ERC20Mock(tokenToBuy).balanceOf(USER);
        uint256 tokenToSellPrevAmount = ERC20Mock(tokenToSell).balanceOf(USER);

        vm.startPrank(USER);
        ERC20Mock(tokenToSell).approve(address(pool), expectedTokenSelledAmount);
        pool.swap(tokenToSell, expectedTokenSelledAmount, 0);
        vm.stopPrank();

        uint256 tokenToBuyCurrentAmount = ERC20Mock(tokenToBuy).balanceOf(USER);
        uint256 tokenToSellCurrentAmount = ERC20Mock(tokenToSell).balanceOf(USER);

        assertApproxEqAbs(tokenToBuyCurrentAmount, tokenToBuyPrevAmount + amountToBuy, 1e12, "TOKEN TO BUY FAILED");
        assertEq(tokenToSellCurrentAmount, tokenToSellPrevAmount - expectedTokenSelledAmount, "TOKEN TO SELL FAILED");
    }

    function _getAmountToBuy(address _tokenToSell, uint256 _amountToSell) private view returns (uint256) {
        address tokenIn = _tokenToSell;
        address tokenOut = _getOtherToken(_tokenToSell);
        uint256 reservesIn = pool.getTokenReserve(tokenIn);
        uint256 reservesOut = pool.getTokenReserve(tokenOut);

        uint256 amountToSellWithFee = _amountToSell * (10000 - 300) / 10000;
        return (reservesOut * amountToSellWithFee) / (reservesIn + amountToSellWithFee);
    }

    function _getAmountToSell(address _tokenToBuy, uint256 _amountToBuy) private view returns (uint256) {
        address tokenIn = _getOtherToken(_tokenToBuy);
        address tokenOut = _tokenToBuy;
        uint256 reservesIn = pool.getTokenReserve(tokenIn);
        uint256 reservesOut = pool.getTokenReserve(tokenOut);

        //uint256 feeToApply = (10000 - 300) / 10000;
        return (reservesIn * _amountToBuy) / (((reservesOut - _amountToBuy) * (10000 - 300)) / 10000);
        //return (reservesIn * _amountToBuy * 10000) / (((reservesOut - _amountToBuy) * (10000 - 300)));
        // uint256 amountOut = _amountToBuy;
        // return (reservesIn * amountOut * 10000) / ((reservesOut - amountOut) * 9700);
    }

    function _getOtherToken(address _token) private view returns (address) {
        return _token == token0 ? token1 : token0;
    }
}
