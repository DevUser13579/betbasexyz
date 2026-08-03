// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./interfaces/IMarketmakerFactory.sol";
import "./MarketmakerBoxLite.sol";

/**
 * @title Marketmaker Box Factory
 * @author betBase community
 * @notice This is a factory contract for deploying new Marketmaker contracts for the Marketmaker system.
 * @notice Multiple contract instances are required to support different betting tokens.
 * @notice It supplies getter functions for quering about the created/deployed contracts.
 * @notice AccessHandler is Initializable.
 */
contract MarketmakerFactory is IMarketmakerFactory, AccessHandler {
    // marketmaker address => marketmakerBox address
    mapping(address => address) public marketmakerBoxes;
    address[] private _marketmakers;
    address private _marketHandler;
    address private _parlayMarketHandler;
    address public betBox; // Address of the bet box, where all tokens are locked, when reserved for markets.
    address public token;

    /**
     * @notice Simple default constructor.
     */
    constructor() AccessHandler() {}

    /**
     * @notice Initializes the contract after setting tokengating and references to other contracts.
     * @param inMarketHandler The handler that creates markets, gets MARKETS_ROLE role in created MMBox.
     * @param inParlayMarketHandler The handler that creates full parlays, gets MARKETS_ROLE role in created MMBox.
     * @param inToken The Token handled by created boxes, stored before using them for markets.
     * @param inBetBox The external box for tokens invested in markets.
     */
    function init(address inMarketHandler, address inParlayMarketHandler, address inToken, address inBetBox)
         external
         onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setMarketHandler(inMarketHandler);
        _setParlayMarketHandler(inParlayMarketHandler);
        _setToken(inToken);
        _setBetBox(inBetBox);
        BaseInitializer.initialize();
    }

    /**
     * @notice Creates/deploys a new MarketmakerBoxLite contract.
     * @notice It is added to the hash list and initialized with roles etc.
     * @return address of the new contract.
     */
    function createMarketmakerBox() external isInitialized whenNotPaused returns (address) {
        return _createMMBox(msg.sender);
    }

    /**
     * @notice Creates/deploys a new MarketmakerBoxLite contract.
     * @notice It is added to the hash list and initialized with roles etc.
     * @param inOwner the address of the new owner.
     * @return address of the new contract.
     */
    function createMarketmakerBoxForUser(address inOwner)
        external
        isInitialized
        onlyRole(OPERATION_ADMIN_ROLE)
        returns (address)
    {
        return _createMMBox(inOwner);
    }

    /**
     * @notice Return the full list of all MarketmakerBoxLite contracts created by this factory.
     * @return address array of the contracts.
     */
    function getMarketmakerList() external view returns (address[] memory) {
        return _marketmakers;
    }

    /**
     * @notice Checks if an address has created a MarketmakerBoxLite contract from this factory.
     * @param inMarketmaker is the address to check.
     * @return bool is true if it matches, false if not.
     */
    function isMarketmaker(address inMarketmaker) external view returns (bool) {
        return marketmakerBoxes[inMarketmaker] != ZERO_ADDRESS;
    }

    function _createMMBox(address marketmaker) private returns (address) {
        if (marketmaker == ZERO_ADDRESS) revert InvalidZeroAddress();
        // Exists?
        if (marketmakerBoxes[marketmaker] != ZERO_ADDRESS) {
            address existingBox = marketmakerBoxes[marketmaker];
            emit MarketmakerBoxExists(existingBox, marketmaker);
            return existingBox;
        }

        MarketmakerBoxLite mmBox = new MarketmakerBoxLite();
        marketmakerBoxes[marketmaker] = address(mmBox);
        _marketmakers.push(marketmaker);

        // Make sure the market controlling contracts are allowed to transfer tokens to/from the betbox.
        mmBox.grantRole(MARKETS_ROLE, _marketHandler);
        mmBox.grantRole(MARKETS_ROLE, _parlayMarketHandler);
        // Init the contract and make the owner full admin for the new contract.
        mmBox.init(marketmaker, token, betBox);
        // Revoke the admin roles for the factory in the new contract.
        mmBox.revokeRole(OPERATION_ADMIN_ROLE, address(this));
        mmBox.revokeRole(PAUSER_ROLE, address(this));
        mmBox.revokeRole(DEFAULT_ADMIN_ROLE, address(this));

        emit MarketmakerBoxCreated(address(mmBox), marketmaker);
        return address(mmBox);
    }

    /**
     * @notice Setter to change the referenced currency Token contract.
     * @param inToken The Token contract address.
     */
    function _setToken(address inToken) private {
        emit SetToken(inToken);
        token = inToken;
    }

    /**
     * @notice Setter to change the referenced BetBox (LockBox) contract.
     * @param inBetBox The BetBox contract address.
     */
    function _setBetBox(address inBetBox) private {
        emit SetBetBox(inBetBox);
        betBox = inBetBox;
    }

    /**
     * @notice Setter to change the referenced MarketHandler contract.
     * @param inMarketHandler The MarketHandler contract address.
     */
    function _setMarketHandler(address inMarketHandler) private {
        emit SetMarketHandler(inMarketHandler);
        _marketHandler = inMarketHandler;
    }

    /**
     * @notice Setter to change the referenced ParlayMarketHandler contract.
     * @param inParlayMarketHandler The ParlayMarketHandler contract address.
     */
    function _setParlayMarketHandler(address inParlayMarketHandler) private {
        emit SetParlayMarketHandler(inParlayMarketHandler);
        _parlayMarketHandler = inParlayMarketHandler;
    }
}
