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

interface ILPToken {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

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

    //Token pair addresses
    address s_token0;
    address s_token1;

    //LP Token
    address s_lpToken;

    //Reserves of token pairs.
    uint256 s_reserveToken0;
    uint256 s_reserveToken1;

    uint256 public constant PRICE_PRECISION_SCALE = 1e10;
    uint256 public constant FEE_BPS = 300;
    uint256 private constant BPS_PRECISION = 10_000;

    constructor(address _t0, address _t1, address _lp) {
        s_token0 = _t0;
        s_token1 = _t1;
        s_reserveToken0 = 0;
        s_reserveToken1 = 0;
        s_lpToken = _lp;

        console.log("POOL ADDRESS INSIDE:", address(this));
    }

    /////////////
    //External//
    ///////////

    /**
     * @dev This function adds liquidity to the pool.
     * @param _t0Deposit deposit amount for token0.
     * @param _t1Deposit deposit amount for token1.
     */
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

        emit LiquidityAdded(msg.sender, t0AmountUsed, t1AmountUsed);
    }

    /**
     * @dev Removes or retrieves liquidity from the pool. The protocol returns to the user its pool proportion,
     * which is measured by the LP token. This pool proportion includes: the user's original liquidity + acumulated
     * fees.
     * @param _liquidityToRetrieve Amount of LP user token. This LP token represents the user`s pool percentaje.
     */
    function removeLiquidity(uint256 _liquidityToRetrieve) external {
        if (_liquidityToRetrieve == 0) {
            revert Pool__LiquidityToRetrieveMustBeGreaterThanZero();
        }

        uint256 totalLP = ILPToken(s_lpToken).totalSupply();
        if (totalLP == 0) {
            revert Pool__ThereIsNotLiquidityInTheSystem();
        }

        uint256 userLP = ILPToken(s_lpToken).balanceOf(msg.sender);
        if (_liquidityToRetrieve > userLP) {
            revert Pool__ProvidedLiquidityExceedsUserLiquidity();
        }

        uint256 reserve0Proportion = (_liquidityToRetrieve * s_reserveToken0) / totalLP;
        uint256 reserve1Proportion = (_liquidityToRetrieve * s_reserveToken1) / totalLP;

        ILPToken(s_lpToken).burn(msg.sender, _liquidityToRetrieve); //Check call security

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

    /**
     * @dev Swaps the specified token in amount by a token out amount. This function allows a user to exchange
     * both tokens in the pool. The specified tokenIn is the token the user wants to exchange or swap by the other
     * token.
     * @param _tokenIn token to swap.
     * @param _amountTokenIn The amount of tokenIn you want to swap.
     */
    function swap(address _tokenIn, uint256 _amountTokenIn) external {
        address token0 = s_token0;
        address token1 = s_token1;

        uint256 totalLP = ILPToken(s_lpToken).totalSupply();
        if (totalLP == 0) {
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

        if (_tokenIn == token0) {
            tokenIn = token0;
            tokenOut = token1;
            (s_reserveToken0, s_reserveToken1, userRecv) = _swap(s_reserveToken0, s_reserveToken1, _amountTokenIn);
        } else {
            tokenIn = token1;
            tokenOut = token0;
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

    /**
     * @dev This is the mint LP token function used by the addLiquidity() function. It calculates the new
     * users' pool proportion based on the deposited amount and the current reserves amounts. The LP token is used to measure
     * this pool proportion. The function picks the minimum proportion supplied between both token deposit amounts.
     * And then, applies this minimum proportion to both deposits. So the final deposit proportion will be the same
     * on both tokens .This is because we need to balance or maintain the pool proportion after the deposit (the
     * pool proportion must be the same before and after the liquidity addition) in order to maintain the pool price.
     * @param _t0Deposit Token 0 deposit amount.
     * @param _t1Deposit Token 1 deposit amount.
     * @return r_t0Used Token 0 deposit amount adjusted and used. It may be adjusted because of the minimum proportion picked.
     * @return r_t1Used Token 1 deposit amount adjusted and used. It may be adjusted because of the minimum proportion picked.
     */
    function _mintLP(uint256 _t0Deposit, uint256 _t1Deposit) private returns (uint256 r_t0Used, uint256 r_t1Used) {
        uint256 lpToMint;
        uint256 totalLP = ILPToken(s_lpToken).totalSupply();

        if (totalLP == 0) {
            lpToMint = Math.sqrt(_t0Deposit * _t1Deposit);
            r_t0Used = _t0Deposit;
            r_t1Used = _t1Deposit;
        } else {
            uint256 lp0 = (_t0Deposit * totalLP) / s_reserveToken0;
            uint256 lp1 = (_t1Deposit * totalLP) / s_reserveToken1;
            lpToMint = Math.min(lp0, lp1);
            r_t0Used = (lpToMint * s_reserveToken0) / totalLP;
            r_t1Used = (lpToMint * s_reserveToken1) / totalLP;
        }

        ILPToken(s_lpToken).mint(msg.sender, lpToMint);
    }

    /**
     * @dev This is the main function that calculates a swap between both tokens. It uses the classical x * y = k
     * formula to calculate the swap. This _swap function it is generic, meaning that can operate with both tokens.
     * We specify the tokenIn as the token we want to trade/swap and the tokenOut as the token we want to receive
     * in the exchange.
     * @param _reserveTokenIn Represents the tokenIn reserves in the system. It is filled from its public function swap().
     * @param _reserveTokenOut Represents the tokenOut reserves in the system. It is filled from its public function swap().
     * @param _amountTokenIn Represents the tokenIn amount we want to swap. It is filled from its public function swap().
     * @return reserveTokenIn_new Represents the new tokenIn reserves after the swap. The user adds tokenIn to swap.
     * @return reserveTokenOut_new Represents the new tokenOut reserves after the swap. The user "takes" tokenOut when swaps.
     * @return rec It is the tokenOut amount the user takes or receives after the swap. When the user swaps tokenIn amount
     * it will receive tokenOut based on the x*y=k proportion.
     */
    function _swap(uint256 _reserveTokenIn, uint256 _reserveTokenOut, uint256 _amountTokenIn)
        private
        pure
        returns (uint256 reserveTokenIn_new, uint256 reserveTokenOut_new, uint256 rec)
    {
        // t0 * t1 = k --> t1 = k/t0
        //tokenOut = k / tokenIn;

        uint256 amountInAfterFee = _amountTokenIn * (BPS_PRECISION - FEE_BPS) / BPS_PRECISION;
        rec = (_reserveTokenOut * amountInAfterFee) / (_reserveTokenIn + amountInAfterFee);

        if (rec == 0) {
            revert Pool__SwapAmountTooSmall();
        }

        //Maybe add a check if rec >= _reserveTokenOut and revert

        reserveTokenIn_new = _reserveTokenIn + _amountTokenIn;
        reserveTokenOut_new = _reserveTokenOut - rec;
    }

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
    function getK() public view returns (uint256) {
        return s_reserveToken0 * s_reserveToken1;
    }

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

    function getLPToken() external view returns (address) {
        return s_lpToken;
    }

    function getReservePairs() external view returns (uint256, uint256) {
        return (s_reserveToken0, s_reserveToken1);
    }

    function getTotalLP() public view returns (uint256) {
        return ILPToken(s_lpToken).totalSupply();
    }

    function getUserLP() public view returns (uint256) {
        return ILPToken(s_lpToken).balanceOf(msg.sender);
    }

    function getUserLP(address user) public view returns (uint256) {
        return ILPToken(s_lpToken).balanceOf(user);
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
}
