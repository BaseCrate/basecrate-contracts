// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;
import "@openzeppelin/contracts/utils/math/Math.sol";
import "hardhat/console.sol";
import "./Baskets.sol";
import "./SwapUniswapV3.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract Subscribe is Baskets, Swap {
    using Math for uint256;
    address private constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    mapping(address => mapping(address => address)) tokenToLinkPriceAddress; // first leg to second leg to chainlink oracle address
    mapping(address => mapping(string => mapping(address => uint256))) public userToHolding; // user to basketid and to a mapping with token address to amount
    mapping(address => mapping(string => address[])) userToActiveTokenArray; // user to basketid and to a mapping with token address to amount
    mapping(address => mapping(string => mapping(address => uint256))) userToTokenIndex; // track userToActiveTokenArray index position for tokens + 1, so 0 is no holding
    mapping(string => mapping(address => uint256)) basketToWeight; //temp utility mapping, basket to token to weight

    /// @dev Break basket information into token array, and component amount array so that we can send trades
    function basketToComponent(string memory _basketID, uint256 _amount)
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        Baskets.Basket memory basket = getBasketById(_basketID);
        address[] memory tokenArray = basket.tokens;
        uint256[] memory weightArray = basket.weights;
        uint256[] memory amountArray = new uint256[](tokenArray.length);

        for (uint256 i = 0; i < tokenArray.length; i++) {
            amountArray[i] = (_amount * weightArray[i]) / 100;
        }
        return (tokenArray, amountArray);
    }

    /// @dev helper function on transaction, _buy is a boolean on buy or sell
    function transaction(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        bool _buy,
        string memory _basketID
    ) internal {
        require(_amountIn > 0, "amount has to be positive");

        if (_tokenIn == address(0) && _buy) {
            uint256 amountOut = Swap.convertExactEthToToken(_tokenOut, _amountIn);
            if (userToHolding[msg.sender][_basketID][_tokenOut] == 0) {
                userToActiveTokenArray[msg.sender][_basketID].push(_tokenOut);
                userToTokenIndex[msg.sender][_basketID][_tokenOut] = userToActiveTokenArray[msg.sender][_basketID].length;
            }
            userToHolding[msg.sender][_basketID][_tokenOut] += amountOut;
        } else {
            uint256 amountOut = Swap.swapExactTokenInForTokenOut(_tokenIn, _tokenOut, _amountIn);
            if (_buy) {
                if (userToHolding[msg.sender][_basketID][_tokenOut] == 0) {
                    userToActiveTokenArray[msg.sender][_basketID].push(_tokenOut);
                    userToTokenIndex[msg.sender][_basketID][_tokenOut] = userToActiveTokenArray[msg.sender][_basketID].length;
                }
                userToHolding[msg.sender][_basketID][_tokenOut] += amountOut;
            } else {
                userToHolding[msg.sender][_basketID][_tokenIn] -= _amountIn;
                if (userToHolding[msg.sender][_basketID][_tokenIn] == 0) {
                    delete userToActiveTokenArray[msg.sender][_basketID][userToTokenIndex[msg.sender][_basketID][_tokenIn] - 1];
                    userToTokenIndex[msg.sender][_basketID][_tokenIn] = 0;
                }
            }
        }
    }

    /// execute the trades when user decides to deposit certain amount to a basket
    function deposit(
        string memory _basketID,
        address _tokenIn,
        uint256 _amount
    ) external payable {
        require(_amount > 0, "amount has to be positive");
        (address[] memory tokenArray, uint256[] memory amountArray) = basketToComponent(_basketID, _amount);

        for (uint256 i = 0; i < tokenArray.length; i++) {
            transaction(_tokenIn, tokenArray[i], amountArray[i], true, _basketID);
        }
    }

    /// only apply if user decides to exit all the holding related to a basket
    function exit(string memory _basketID, address _tokenOut) external {
        require(_tokenOut != address(0), "user can't receive ETH");
        address[] memory tokenArray = userToActiveTokenArray[msg.sender][_basketID];

        for (uint256 i = 0; i < tokenArray.length; i++) {
            if (tokenArray[i] != address(0)) {
                uint256 tokenBalance = Math.min(
                    userToHolding[msg.sender][_basketID][tokenArray[i]],
                    ERC20(tokenArray[i]).balanceOf(msg.sender)
                );

                if (tokenBalance > 0) {
                    transaction(tokenArray[i], _tokenOut, tokenBalance, false, _basketID);
                }
            }
        }
    }

    /// get the price for token vs ETH from chainlink oracle, address of that pair needed
    function getPrice(address _pair) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_pair);
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        return uint256(answer);
    }

    /// get user basket balance in total and in each token (in _balanceToken)
    function getBasketBalance(
        address _userAddress,
        string memory _basketID,
        address _balanceToken
    )
        internal
        view
        returns (
            uint256,
            address[] memory,
            uint256[] memory
        )
    {
        address[] memory activeTokenArray = userToActiveTokenArray[_userAddress][_basketID];
        uint256 totalBalance;
        uint256[] memory tokenBalance = new uint256[](activeTokenArray.length);

        for (uint256 i = 0; i < activeTokenArray.length; i++) {
            address activeToken = activeTokenArray[i];
            if (activeToken != address(0)) {
                uint256 tokenAmountLocal = userToHolding[_userAddress][_basketID][activeToken];
                uint256 tokenAmount = tokenAmountLocal * getPrice(tokenToLinkPriceAddress[_balanceToken][activeToken]);
                tokenBalance[i] = tokenAmount;
                totalBalance += tokenAmount;
            } else {
                tokenBalance[i] = 0;
            }
        }
        return (totalBalance, activeTokenArray, tokenBalance);
    }

    function rebalance(
        string memory _basketID,
        int256 _deltaAmount,
        bool _current,
        address _balanceToken
    ) internal {
        (uint256 balance, address[] memory activeTokenArray, uint256[] memory balanceArray) = getBasketBalance(msg.sender, _basketID, _balanceToken);

        uint256 targetAmount;
        if (_current) {
            targetAmount = balance;
        } else {
            targetAmount = uint256(int256(balance) + _deltaAmount);
        }

        require(int256(balance) + _deltaAmount > 0, "holding not enough to cover sell");

        Baskets.Basket memory basket = getBasketById(_basketID);

        for (uint256 i = 0; i < basket.tokens.length; i++) {
            basketToWeight[_basketID][basket.tokens[i]] = basket.weights[i];

            if (userToTokenIndex[msg.sender][_basketID][basket.tokens[i]] == 0) {
                transaction(_balanceToken, basket.tokens[i], (targetAmount * basket.weights[i]) / 100, true, _basketID);
            }
        }

        for (uint256 i = 0; i < activeTokenArray.length; i++) {
            if (activeTokenArray[i] != address(0)) {
                if (basketToWeight[_basketID][activeTokenArray[i]] == 0 && balanceArray[i] > 0) {
                    transaction(
                        activeTokenArray[i],
                        _balanceToken,
                        balanceArray[i] / getPrice(tokenToLinkPriceAddress[_balanceToken][activeTokenArray[i]]),
                        false,
                        _basketID
                    );
                } else {
                    int256 tokenBalanceAmount = int256(((targetAmount * basket.weights[i]) / 100) - balanceArray[i]);
                    if (tokenBalanceAmount > 0) {
                        transaction(_balanceToken, activeTokenArray[i], uint256(tokenBalanceAmount), true, _basketID);
                    } else {
                        transaction(
                            activeTokenArray[i],
                            _balanceToken,
                            uint256(tokenBalanceAmount) / getPrice(tokenToLinkPriceAddress[_balanceToken][activeTokenArray[i]]),
                            false,
                            _basketID
                        );
                    }
                }
            }
        }
    }

    function add(
        string memory _basketID,
        address _tokenIn,
        uint256 _amountAdd
    ) external payable {
        rebalance(_basketID, int256(_amountAdd), false, _tokenIn);
    }

    function sell(
        string memory _basketID,
        address _tokenOut,
        uint256 _amountSell
    ) external payable {
        rebalance(_basketID, -int256(_amountSell), false, _tokenOut);
    }
}
