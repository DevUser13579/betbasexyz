// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IMarketmakerFactory {
    /**
     * @notice Event that fires when the MarketHandler is set.
     * @param add is the new address.
     */
    event SetMarketHandler(address add);

    /**
     * @notice Event that fires when the ParlayMarketHandler is set.
     * @param add is the new address.
     */
    event SetParlayMarketHandler(address add);

    /**
     * @notice Event that fires when the BetBox is set.
     * @param add is the new address.
     */
    event SetBetBox(address add);

    /**
     * @notice Event that fires when the Token is set.
     * @param add is the new address.
     */
    event SetToken(address add);

    /**
     * @notice Event that fires when trying to create a duplicate Marketmaker contract.
     * @param marketmakerBox is the existing MarketmakerBoxLite contract address.
     * @param marketmaker is the existing marketmaker wallet address.
     */
    event MarketmakerBoxExists(address indexed marketmakerBox, address indexed marketmaker);

    /**
     * @notice Event that fires when a new Marketmaker contract is created.
     * @param marketmakerBox is the new MarketmakerBoxLite contract address.
     * @param marketmaker is the new marketmaker wallet address.
     */
    event MarketmakerBoxCreated(address indexed marketmakerBox, address indexed marketmaker);

    /**
     * @notice Error when trying to add a MarketmakerBoxLite for the zero address.
     */
    error InvalidZeroAddress();

    function createMarketmakerBox() external returns (address);
    function createMarketmakerBoxForUser(address) external returns (address);

    // Public accessors to box mapping and contracts
    function marketmakerBoxes(address) external view returns (address);
    function betBox() external view returns (address);
    function token() external view returns (address);

    function getMarketmakerList() external view returns (address[] memory);
    function isMarketmaker(address) external view returns (bool);
}
