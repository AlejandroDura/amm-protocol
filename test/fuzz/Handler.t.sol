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

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

contract Handler is Test {
    Pool public pool;
    address token0;
    address token1;

    mapping(address => uint256) public usersLP;
    uint256 public totalLP;
    uint256 public userLP;

    address[] public users;
    address[] public usersWithLiquidity;
    //uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 MAX_DEPOSIT_SIZE = 1e30;

    uint256 public timesAddLiquidityCalled;

    constructor(Pool _pool, address[] memory u) {
        pool = _pool;
        (token0, token1) = pool.getTokenPairs();

        users = u;
    }

    function addLiquidity(uint256 _t0Deposit, uint256 _t1Deposit, uint256 _userIndex) external {
        address user = users[_userIndex % users.length];
        uint256 depositT0Adjusted = bound(_t0Deposit, 1e6, MAX_DEPOSIT_SIZE);
        (uint256 r0, uint256 r1) = pool.getReservePairs();
        if (r0 == 0) {
            r0 = depositT0Adjusted;
            r1 = r0;
        }
        uint256 depositT1Adjusted = depositT0Adjusted * r1 / r0;

        vm.startPrank(user);
        ERC20Mock(token0).mint(user, depositT0Adjusted);
        ERC20Mock(token1).mint(user, depositT1Adjusted);

        ERC20Mock(token0).approve(address(pool), depositT0Adjusted);
        ERC20Mock(token1).approve(address(pool), depositT1Adjusted);

        pool.addLiquidity(depositT0Adjusted, depositT1Adjusted);
        vm.stopPrank();
    }

    function swap(uint256 _userIndex, uint256 _tokenSeed, uint256 _amountToSwap) public {
        if (pool.getTotalLP() == 0) {
            return;
        }

        address user = users[_userIndex % users.length];
        address token = _getTokenFromSeed(_tokenSeed);

        uint256 min = pool.getTokenReserves(token) / 1e6;
        uint256 max = pool.getTokenReserves(token) / 10;

        uint256 otherTokenReserve = pool.getTokenReserves(_getTheOtherToken(token));

       // if((otherTokenReserve / 2) < 10) return;
       if(otherTokenReserve < 500) return;

        uint256 amountToSwapAdjusted = bound(_amountToSwap, 100, otherTokenReserve / 2);

        vm.startPrank(user);
        ERC20Mock(token).mint(user, amountToSwapAdjusted);
        ERC20Mock(token).approve(address(pool), amountToSwapAdjusted);

        pool.swap(token, amountToSwapAdjusted);
        vm.stopPrank();
    }

    function removeLiquidity(uint256 _userIndex, uint256 _liquidityToRetrieve) public {
        uint256 totalLiquidity = pool.getTotalLP();
        if (totalLiquidity == 0) return;

        address user = users[_userIndex % users.length];
        uint256 userLP = pool.getUserLP(user);
        if (userLP == 0) return;

        uint256 liquiditySanitized = bound(_liquidityToRetrieve, 1, userLP);

        vm.startPrank(user);
        pool.removeLiquidity(liquiditySanitized);
        vm.stopPrank();
    }

    function _getTokenFromSeed(uint256 _tokenSeed) private view returns (address) {
        if (_tokenSeed % 2 == 0) {
            return token0;
        }

        return token1;
    }

    function getUser(uint256 _index) public view returns (address) {
        return users[_index];
    }

    function getUsersLength() public view returns (uint256) {
        return users.length;
    }

    function getUsersWithLiquidity() public view returns (address[] memory) {
        return usersWithLiquidity;
    }

    function _getTheOtherToken(address _token) private view returns (address) {
        if (_token == token0) {
            return token1;
        }

        return token0;
    }
}
