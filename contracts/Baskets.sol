// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "hardhat/console.sol";

contract Baskets {
    event basketCreated(address owner, Basket basket);
    
    // Mapping of creators to the baskets created by them
    mapping(address => Basket[]) public creators;

    // Mapping of basketId to Basket
    mapping(string => Basket) public uniqueBasketMapping;

    struct Basket {
        bool active;
        string basketID;
        address[] tokens;
        uint256[] weights;
        address basketOwner;
    }

    /**
        @dev Modifiers to validate the baskets and perform trivial checks before creation
     */
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

    /**
        @notice Creates the Basket with tokens and respective weights
        @dev Pushes the new Basket into the list of Baskets created by the creator
        @param tokens The list of tokens present in the basket
        @param weights Respective weights of Tokens as fixed by the creator
        @param id Unique Id corresponding to the basket
    */
    function createBasket(
        address[] memory tokens,
        uint256[] memory weights,
        string memory id
    ) external validateBasket(tokens, weights, id) validateWeights(weights) {
        Basket memory basket = Basket({
            basketID: id,
            tokens: tokens,
            weights: weights,
            basketOwner: msg.sender,
            active: true
        });

        uniqueBasketMapping[id] = basket; // Create a mapping for unique baskets
        creators[msg.sender].push(basket); // Append to the list of baskets for the particular creator

        emit basketCreated(msg.sender, basket);
    }

    /**
        @dev Change the weights of baskets
     */
    function resetWeights(string memory basketId, uint256[] memory weights)
        external
        validateWeights(weights)
        checkBasketExists(basketId)
    {
        require(
            uniqueBasketMapping[basketId].weights.length == weights.length,
            "New and old basket weights are not of equal lengths"
        );

        require(
            uniqueBasketMapping[basketId].basketOwner == msg.sender,
            "Only the original creator can modify the weights of the basket"
        );
        
        uniqueBasketMapping[basketId].weights = weights;
    }

    /**
        @dev Fetch the struct Basket when called by its Basket Id
     */
    function getBasketById(string memory _basketId)
        public
        view
        checkBasketExists(_basketId)
        returns (Basket memory)
    {
        return uniqueBasketMapping[_basketId];
    }

    /**
        @dev Transfers the ownership of the basket to a new address
     */
    function transferBasketOwnership(address _newOwner, string memory basketId)
        external
        checkBasketExists(basketId)
    {
        require(
            msg.sender == uniqueBasketMapping[basketId].basketOwner,
            "You are not the owner of the basket"
        );

        uniqueBasketMapping[basketId].basketOwner = _newOwner;
        emit basketCreated(msg.sender, uniqueBasketMapping[basketId]); // Emit event for ownership transfer
    }
}
