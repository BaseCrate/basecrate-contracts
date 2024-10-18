// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract Swap {
    /**
        @dev Router used to interact with V3 pools and perform Swaps
    */
    ISwapRouter public constant uniswapRouter =
        ISwapRouter(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E); // Sepolia router
    address private constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // Sepolia WETH address

    function getExactInputSingleParams(
        address _tokenOut,
        uint256 _amountIn,
        address _tokenIn
    ) internal view returns (ISwapRouter.ExactInputSingleParams memory) {
        uint256 deadline = block.timestamp + 15; // Short deadline for testnet convenience
        address tokenIn = _tokenIn == address(0) ? WETH : _tokenIn;
        uint24 fee = 3000; // Standard Uniswap V3 fee tier
        address recipient = msg.sender;
        uint256 amountOutMinimum = 1;
        uint160 sqrtPriceLimitX96 = 0;

        return ISwapRouter.ExactInputSingleParams(
            tokenIn,
            _tokenOut,
            fee,
            recipient,
            deadline,
            _amountIn,
            amountOutMinimum,
            sqrtPriceLimitX96
        );
    }

    /**
        @notice Swaps `amountIn` of one _tokenIn for as much as possible of another token _tokenOut
        @return amountOut The amount of the received token (_tokenOut)
     */
    function swapExactTokenInForTokenOut(
        address _tokenIn,
        address _tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        require(amountIn > 0, "Must pass non 0 input amount");

        // Check allowance for tokenIn
        uint256 allowance = IERC20(_tokenIn).allowance(msg.sender, address(this));
        require(allowance >= amountIn, "Check the token allowance");

        // Transfer tokenIn to this contract
        TransferHelper.safeTransferFrom(_tokenIn, msg.sender, address(this), amountIn);

        // Approve the router to spend tokenIn
        TransferHelper.safeApprove(_tokenIn, address(uniswapRouter), amountIn);

        // Perform the swap
        ISwapRouter.ExactInputSingleParams memory params = getExactInputSingleParams(
            _tokenOut,
            amountIn,
            _tokenIn
        );
        amountOut = uniswapRouter.exactInputSingle(params);
        return amountOut;
    }

    /**
        @notice Swaps `amountIn` of ETH (WETH) for as much as possible of _tokenOut
        @return amountOut The amount of the received token (_tokenOut)
     */
    function convertExactEthToToken(address _tokenOut, uint256 _amountIn)
        internal
        returns (uint256 amountOut)
    {
        require(_amountIn > 0, "Must pass non 0 input amount");

        // Swap ETH for the token
        ISwapRouter.ExactInputSingleParams memory params = getExactInputSingleParams(
            _tokenOut,
            _amountIn,
            address(0) // Pass 0 for ETH
        );
        amountOut = uniswapRouter.exactInputSingle{value: _amountIn}(params);
        return amountOut;
    }
}
