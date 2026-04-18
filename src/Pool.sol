// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "forge-std/console.sol";

contract Pool {
    ///////////
    //Errors//
    /////////
    error Pool__NewDepositsMustBeGreaterThanZero(uint256, uint256);
    error Pool__TokenTransferFailed(address);
    error Pool__TokenPairUsdValueMustBeTheSame();
    error Pool__ProvidedLiquidityExceedsUserLiquidity();
    error Pool__ThereIsNotLiquidityInTheSystem();
    error Pool__LiquidityToRetrieveMustBeGreaterThanZero();
    error Pool__TokenAmountMustBeGreaterThanZero();
    error Pool__ProvidedTokenDoesNotExists();
    error Pool__SwapAmountTooSmall();
    error Pool__LiquidityToRemoveTooSmall();

    ///////////
    //Events//
    /////////
    event LiquidityAdded(address indexed user, uint256 indexed amount0, uint256 indexed amount1);

    address s_token0;
    address s_token1;
    uint256 s_reserveToken0;
    uint256 s_reserveToken1;

    uint256 s_LP_totalSupply;
    mapping(address => uint256) s_userLPSupply;
    address[] public usersParticipated;

    uint256 public constant PRICE_PRECISION_SCALE = 1e10;
    uint256 public constant FEE = 3;
    uint256 private constant PERCENTAGE_PRECISION = 100;

    constructor(address t0, address t1) {
        s_token0 = t0;
        s_token1 = t1;
        s_reserveToken0 = 0;
        s_reserveToken1 = 0;

        console.log("POOL ADDRESS INSIDE:", address(this));
    }

    /////////////
    //External//
    ///////////

    function addLiquidity(uint256 _t0Deposit, uint256 _t1Deposit) external {
        if (_t0Deposit == 0 || _t1Deposit == 0) {
            revert Pool__NewDepositsMustBeGreaterThanZero(_t0Deposit, _t1Deposit);
        }

        (uint256 t0AmountUsed, uint256 t1AmountUsed) = _mintLP(_t0Deposit, _t1Deposit);

        s_reserveToken0 += t0AmountUsed;
        s_reserveToken1 += t1AmountUsed;

        bool success = IERC20(s_token0).transferFrom(msg.sender, address(this), t0AmountUsed);
        if (!success) {
            revert Pool__TokenTransferFailed(s_token0);
        }

        success = IERC20(s_token1).transferFrom(msg.sender, address(this), t1AmountUsed);
        if (!success) {
            revert Pool__TokenTransferFailed(s_token1);
        }

        console.log("POOL msg.sender:", msg.sender);
        // console.log("msg.sender in pool:", msg.sender);
        //console.log("LP balance of msg.sender", getUserLP(msg.sender));
        emit LiquidityAdded(msg.sender, t0AmountUsed, t1AmountUsed);
    }

    //We need to change or modify this by adding LP token mechanism to determine the % the user has in the pool
    function removeLiquidity(uint256 _liquidityToRetrieve) external {
        if (_liquidityToRetrieve == 0) {
            revert Pool__LiquidityToRetrieveMustBeGreaterThanZero();
        }

        if (s_LP_totalSupply == 0) {
            revert Pool__ThereIsNotLiquidityInTheSystem();
        }

        if (_liquidityToRetrieve > s_userLPSupply[msg.sender]) {
            revert Pool__ProvidedLiquidityExceedsUserLiquidity();
        }

        uint256 reserve0Proportion = (_liquidityToRetrieve * s_reserveToken0) / s_LP_totalSupply;
        uint256 reserve1Proportion = (_liquidityToRetrieve * s_reserveToken1) / s_LP_totalSupply;

        s_userLPSupply[msg.sender] -= _liquidityToRetrieve;
        s_LP_totalSupply -= _liquidityToRetrieve;

        s_reserveToken0 -= reserve0Proportion;
        s_reserveToken1 -= reserve1Proportion;

        bool success = IERC20(s_token0).transfer(msg.sender, reserve0Proportion);
        if (!success) {
            revert Pool__TokenTransferFailed(s_token0);
        }

        success = IERC20(s_token1).transfer(msg.sender, reserve1Proportion);
        if (!success) {
            revert Pool__TokenTransferFailed(s_token1);
        }
    }

    function swap(address _tokenIn, uint256 _amountTokenIn) external {
        address token0 = s_token0;
        address token1 = s_token1;

        if (s_LP_totalSupply == 0) {
            revert Pool__ThereIsNotLiquidityInTheSystem();
        }

        if (_amountTokenIn <= 0) {
            revert Pool__TokenAmountMustBeGreaterThanZero();
        }

        if (_tokenIn != token0 && _tokenIn != token1) {
            revert Pool__ProvidedTokenDoesNotExists();
        }

        address tokenIn;
        address tokenOut;
        uint256 userRecv;

        if (_tokenIn == s_token0) {
            tokenIn = s_token0;
            tokenOut = s_token1;
            (s_reserveToken0, s_reserveToken1, userRecv) = _swap(s_reserveToken0, s_reserveToken1, _amountTokenIn);
        } else {
            tokenIn = s_token1;
            tokenOut = s_token0;
            (s_reserveToken1, s_reserveToken0, userRecv) = _swap(s_reserveToken1, s_reserveToken0, _amountTokenIn);
        }

        bool success = IERC20(tokenIn).transferFrom(msg.sender, address(this), _amountTokenIn);
        if (!success) {
            revert Pool__TokenTransferFailed(tokenIn);
        }

        success = IERC20(tokenOut).transfer(msg.sender, userRecv);
        if (!success) {
            revert Pool__TokenTransferFailed(tokenOut);
        }
    }

    ////////////
    //Private//
    //////////

    function _getPairsDecimalScale() private view returns (uint256, uint256) {
        uint8 decimals0 = ERC20(s_token0).decimals();
        uint8 decimals1 = ERC20(s_token1).decimals();

        uint256 scale0 = 10 ** (18 - decimals0);
        uint256 scale1 = 10 ** (18 - decimals1);

        return (scale0, scale1);
    }

    function _mintLP(uint256 _t0Deposit, uint256 _t1Deposit) private returns (uint256 t0Used, uint256 t1Used) {
        uint256 lpToMint;

        if (s_LP_totalSupply == 0) {
            lpToMint = Math.sqrt(_t0Deposit * _t1Deposit);
            t0Used = _t0Deposit;
            t1Used = _t1Deposit;
        } else {
            uint256 lp0 = (_t0Deposit * s_LP_totalSupply) / s_reserveToken0;
            uint256 lp1 = (_t1Deposit * s_LP_totalSupply) / s_reserveToken1;
            lpToMint = Math.min(lp0, lp1);
            t0Used = (lpToMint * s_reserveToken0) / s_LP_totalSupply;
            t1Used = (lpToMint * s_reserveToken1) / s_LP_totalSupply;
        }

        s_LP_totalSupply += lpToMint;
        s_userLPSupply[msg.sender] += lpToMint;
        usersParticipated.push(msg.sender);
    }

    //Introduce t0 and receive t1.
    function _swap(uint256 _reserveTokenIn, uint256 _reserveTokenOut, uint256 _amountTokenIn)
        private
        pure
        returns (uint256 reserveTokenIn_new, uint256 reserveTokenOut_new, uint256 rec)
    {
        // t0 * t1 = k --> t1 = k/t0
        //tokenOut = k / tokenIn;
        // uint256 amountInWithFee = _amountTokenIn * (PERCENTAGE_PRECISION - FEE) / PERCENTAGE_PRECISION;
        // reserveTokenIn_new = _reserveTokenIn + _amountTokenIn;
        // reserveTokenOut_new = (_reserveTokenIn * _reserveTokenOut) / (_reserveTokenIn + amountInWithFee);

        // rec = _reserveTokenOut - reserveTokenOut_new;

        uint256 amountInWithFee = _amountTokenIn * (PERCENTAGE_PRECISION - FEE) / PERCENTAGE_PRECISION;
        rec = (_reserveTokenOut * amountInWithFee) / (_reserveTokenIn + amountInWithFee);

        if (rec == 0) {
            revert Pool__SwapAmountTooSmall();
        }

        reserveTokenIn_new = _reserveTokenIn + _amountTokenIn;
        reserveTokenOut_new = _reserveTokenOut - rec;
    }

    function _swapTokenAmounts(uint256 _t0Amount, uint256 _t1Amount) private {}

    /////////
    //Test//
    ///////
    function mintLP(uint256 _t0Deposit, uint256 _t1Deposit) public returns (uint256, uint256) {
        return _mintLP(_t0Deposit, _t1Deposit);
    }

    function setFakeReserves(uint256 _t0Deposit, uint256 _t1Deposit) public {
        s_reserveToken0 += _t0Deposit;
        s_reserveToken1 += _t1Deposit;
    }

    ////////////
    //Getters//
    //////////
    function getPairsDecimals() public view returns (uint8, uint8) {
        uint8 decimals0 = ERC20(s_token0).decimals();
        uint8 decimals1 = ERC20(s_token1).decimals();

        return (decimals0, decimals1);
    }

    function getPairsDecimalScale() public view returns (uint256, uint256) {
        return _getPairsDecimalScale();
    }

    function getTokenPairs() external view returns (address, address) {
        return (s_token0, s_token1);
    }

    function getReservePairs() external view returns (uint256, uint256) {
        return (s_reserveToken0, s_reserveToken1);
    }

    function getTotalLP() public view returns (uint256) {
        return s_LP_totalSupply;
    }

    function getUserLP() public view returns (uint256) {
        return s_userLPSupply[msg.sender];
    }

    function getUserLP(address user) public view returns (uint256) {
        return s_userLPSupply[user];
    }

    function getTheTokenUserLP(address _user) public view returns (uint256) {
        return s_LP_totalSupply;
    }

    function getUserReservesToRemove(address user) public view returns (uint256 token0Amount, uint256 token1Amount) {
        uint256 userLP = getUserLP(user);
        token0Amount = (userLP * s_reserveToken0) / s_LP_totalSupply;
        token1Amount = (userLP * s_reserveToken1) / s_LP_totalSupply;
    }

    function getTokenReserves(address _token) public view returns (uint256) {
        if (_token != s_token0 && _token != s_token1) {
            revert Pool__ProvidedTokenDoesNotExists();
        }

        if (_token == s_token0) {
            return s_reserveToken0;
        }

        return s_reserveToken1;
    }

    function getUsersParticipated() public view {
        //address[] memory users = usersParticipated;
        for (uint256 i = 0; i < usersParticipated.length; i++) {
            console.log("Usuarios participantes dentro del pool: ", usersParticipated[i]);
        }
    }

    function getUsersParticipatedTotalLP() public view returns (uint256) {
        //address[] memory users = usersParticipated;
        uint256 sum;
        for (uint256 i = 0; i < usersParticipated.length; i++) {
            sum += s_userLPSupply[usersParticipated[i]];
        }
        return sum;
    }
}
