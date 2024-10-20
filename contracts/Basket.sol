// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./Pool.sol";

contract Baskets {
    event BasketCreated(address owner, Basket basket);
    event TokenDeposited(address indexed basketOwner, string indexed basketId, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
    event GetToken(address token);


    // Mapping of creators to the baskets created by them
    mapping(address => Basket[]) public creators;
   
    // Mapping of basketId to Basket
    mapping(string => Basket) public uniqueBasketMapping;

    // Mapping of basketId to the basket's owner address
    mapping(string => address) public basketToOwner;

    // Mapping of creators to the baskets created by them
   address private constant weth =  0x41181b2148ACA90F8d7A9559c2BA92BDFF4b57e4 ;
   address private constant moto = 0xAB1d05a66b93353eFf8ea519D4675a362c761894 ; 


    struct Basket {
        bool active;
        string basketID;
        address[] tokens;
        uint256[] balances;  // Track token balances for each token in the basket
        uint256[] weights;
        address basketOwner;
        address pool;  // Specific pool for this basket
    }

    modifier checkBasketExists(string memory id) {
        require(uniqueBasketMapping[id].active, "Basket does not exist");
        _;
    }

    modifier validateBasket(
        address[] memory tokens,
        uint256[] memory weights,
        string memory id
    ) {
        require(
            tokens.length == weights.length,
            "All tokens have not been assigned weights"
        );
        require(
            !uniqueBasketMapping[id].active,
            "Identical basket already exists"
        );
        _;
    }

    modifier validateWeights(uint256[] memory weights) {
        uint256 sum = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            require(weights[i] > 0, "Weight must be positive");
            sum += weights[i];
        }
        require(
            sum == 100,
            "Sum of weights of constituents is not equal to 100"
        );
        _;
    }

    

    // Remove the pool from the constructor
    constructor() {}

    function createBasket(
        address[] memory tokens,
        uint256[] memory weights,
        string memory id,
        address poolAddress // Pool address specific to this basket
    ) external validateBasket(tokens, weights, id) validateWeights(weights) {
        Basket memory basket = Basket({
            basketID: id,
            tokens: tokens,
            balances: new uint256[](tokens.length), // Initialize token balances to 0
            weights: weights,
            basketOwner: msg.sender,
            pool: poolAddress,  // Assign the pool to this basket
            active: true
        });

        uniqueBasketMapping[id] = basket;
        creators[msg.sender].push(basket);

        emit BasketCreated(msg.sender, basket);
    }

    function allowWeth(string memory basketId,uint256 amountIn) external {
        Basket storage basket = uniqueBasketMapping[basketId];
        IERC20 WETHBASE = IERC20(weth) ; 
        WETHBASE.approve(basket.pool,amountIn);

    }


    function transferToContract(string memory basketId,uint256 amountIn) external {
        Basket storage basket = uniqueBasketMapping[basketId];
        IERC20 WETHBASE = IERC20(weth) ; 
        WETHBASE.transferFrom(msg.sender, address(this),amountIn);
        
    }

    function alllowToken(string memory basketId,address token, uint256 amount) external {
        Basket storage basket = uniqueBasketMapping[basketId];

         IERC20 WETHBASE = IERC20(token) ; 
        WETHBASE.approve(basket.pool,amount);
    }



    function depositAndSwap(string memory basketId, address tokenIn, uint256 amountIn) external checkBasketExists(basketId) {
        Basket storage basket = uniqueBasketMapping[basketId];
        // Swap tokenIn (Token A) for tokenOut (Token B) via the specific Pool contract of this basket
        Pool poolContract = Pool(basket.pool);  // Use the pool associated with the basket

        poolContract.swap(tokenIn, amountIn);

        // Find which token in the basket matches tokenOut
        (address token0, address token1) = poolContract.getTokens();
        address tokenOut = tokenIn == token0 ? token1 : token0;

        uint256 amountOut = IERC20(tokenOut).balanceOf(address(this));  // Get the new balance after swap

        // // Update the basket with the swapped token's balance
        bool tokenOutExists = false;
        for (uint256 i = 0; i < basket.tokens.length; i++) {
            if (basket.tokens[i] == tokenOut) {
                basket.balances[i] += amountOut;
                tokenOutExists = true;
                break;
            }
        }

        // If tokenOut doesn't exist in the basket, add it
        if (!tokenOutExists) {
            basket.tokens.push(tokenOut);
            basket.balances.push(amountOut);
        }
        
        emit TokenDeposited(msg.sender, basketId, tokenIn, amountIn, tokenOut, amountOut);
    }


            
        function withdraw(string memory basketId, address tokenOut, uint256 amountOut) 
            external 
            checkBasketExists(basketId) 
        {
            Basket storage basket = uniqueBasketMapping[basketId];
            Pool poolContract = Pool(basket.pool);  // Use the pool associated with the basket

            // Check if the basket has enough balance of the tokenOut to swap for WETH
            uint256 tokenBalance = 0;
            for (uint256 i = 0; i < basket.tokens.length; i++) {
                if (basket.tokens[i] == tokenOut) {
                    tokenBalance = basket.balances[i];
                    require(tokenBalance >= amountOut, "Insufficient balance in the basket");
                    break;
                }
            }

            // Perform the swap from tokenOut to WETH if needed
            // Calculate the amount of tokenOut to swap
            if (tokenBalance < amountOut) {
                // Determine the amount of WETH we need to get
                uint256 amountToSwap = amountOut;  // We want to get this amount in WETH
                
                // Swap tokenOut for WETH via the specific Pool contract
                IERC20(tokenOut).approve(address(poolContract), amountToSwap);
                poolContract.swap(tokenOut, amountToSwap);

                // Update the basket with the new balance after the swap
                uint256 newWethBalance = IERC20(weth).balanceOf(address(this));
                // We don't need to update the basket balance for WETH in this case,
                // since we're sending it directly to the user.
            }
            
            // Transfer the WETH to the user
            uint256 wethBalance = IERC20(weth).balanceOf(address(this)); // Get the current WETH balance
            require(wethBalance >= amountOut, "Insufficient WETH balance after swap");

            // Send the specified amount of WETH to the user
            IERC20(weth).transfer(msg.sender, amountOut);

            // Update the basket balance for the withdrawn token
            for (uint256 i = 0; i < basket.tokens.length; i++) {
                if (basket.tokens[i] == tokenOut) {
                    basket.balances[i] -= amountOut; // Decrease the balance of the withdrawn token
                    break;
                }
            }
        }


   // Retrieve a basket by its ID
    function getBasketById(string memory basketId) public view checkBasketExists(basketId) returns (Basket memory) {
        return uniqueBasketMapping[basketId];
    }

    // Retrieve all baskets created by a user
    function getBasketsByUser(address user) public view returns (Basket[] memory) {
        return creators[user];
    }

    // Retrieve the owner of a basket by its ID
    function getOwnerOfBasket(string memory basketId) public view checkBasketExists(basketId) returns (address) {
        return basketToOwner[basketId];
    }
}


