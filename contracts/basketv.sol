// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;
//
// 
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}
// for swapping tokens in basket 
interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract TokenBasketVault {
    ISwapRouter02 public immutable swapRouter;
    address public immutable WETH;

    mapping(string => address[]) public baskets;
    mapping(address => mapping(string => mapping(address => uint256))) public userHoldings;

    event BasketCreated(string basketId, address[] tokens);
    event Invested(address indexed user, string basketId, uint256 amount);
    event Withdrawn(address indexed user, string basketId, address token, uint256 amount);
    event SwapCompleted(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(address _swapRouter, address _WETH) {
        swapRouter = ISwapRouter02(_swapRouter);
        WETH = _WETH;
    }

    function createBasket(string memory basketId, address[] memory tokens) external {
        require(baskets[basketId].length == 0, "Basket already exists");
        require(tokens.length > 0, "Basket must contain at least one token");

        for (uint i = 0; i < tokens.length; i++) {
            require(tokens[i] != address(0), "Invalid token address");
            for (uint j = i + 1; j < tokens.length; j++) {
                require(tokens[i] != tokens[j], "Duplicate tokens not allowed");
            }
        }

        baskets[basketId] = tokens;
        emit BasketCreated(basketId, tokens);
    }
    /// swap eth for token in basket
    function invest(string memory basketId) external payable {
        require(msg.value > 0, "Investment amount must be greater than 0");
        address[] storage basketTokens = baskets[basketId];
        require(basketTokens.length > 0, "Basket does not exist");

        uint256 amountPerToken = msg.value / basketTokens.length;

        for (uint i = 0; i < basketTokens.length; i++) {
            address token = basketTokens[i];
            uint256 amountOut = swapExactInputSingle(WETH, token, amountPerToken);
            userHoldings[msg.sender][basketId][token] += amountOut;
            emit SwapCompleted(WETH, token, amountPerToken, amountOut);
        }

        emit Invested(msg.sender, basketId, msg.value);
    }

    function swapExactInputSingle(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        ISwapRouter02.ExactInputSingleParams memory params = ISwapRouter02.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 15 minutes,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        amountOut = swapRouter.exactInputSingle{value: tokenIn == WETH ? amountIn : 0}(params);
        return amountOut;
    }


    // withdraws 
    function withdraw(string memory basketId, address tokenOut, uint256 amount) external {
        require(amount > 0, "Withdrawal amount must be greater than 0");
        require(userHoldings[msg.sender][basketId][tokenOut] >= amount, "Insufficient balance");

        userHoldings[msg.sender][basketId][tokenOut] -= amount;

        if (tokenOut == WETH) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            require(IERC20(tokenOut).transfer(msg.sender, amount), "Token transfer failed");
        }

        emit Withdrawn(msg.sender, basketId, tokenOut, amount);
    }

    // GET USER holding by basket id and address 
    function getUserHoldings(address user, string memory basketId) external view returns (address[] memory, uint256[] memory) {
        address[] memory basketTokens = baskets[basketId];
        uint256[] memory holdings = new uint256[](basketTokens.length);

        for (uint i = 0; i < basketTokens.length; i++) {
            holdings[i] = userHoldings[user][basketId][basketTokens[i]];
        }

        return (basketTokens, holdings);
    }

    receive() external payable {}
}