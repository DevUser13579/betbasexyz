// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./utils/IAccessHandler.sol";

interface IMarketmakerBox is IAccessHandler {
    /**
     * @notice Event that fires when the token is set.
     * @param add is the new address.
     */
    event SetToken(address add);

    /**
     * @notice Event that fires when the BetBox is set.
     * @param add is the new address.
     */
    event SetBetBox(address add);

    /**
     * @notice Event that fires when tokens are deposited.
     * @param owner is the address that depposited tokens.
     * @param tokenAdd is the token contract address.
     * @param amount is the amount deposited.
     */
    event TokensDeposited(address indexed owner, address tokenAdd, uint256 amount);

    /**
     * @notice Event that fires when tokens are deposited.
     * @param owner is the address that withdrew tokens.
     * @param tokenAdd is the token contract address.
     * @param amount is the amount withdrawn.
     */
    event TokensWithdrawn(address indexed owner, address tokenAdd, uint256 amount);

    /**
     * @notice Event fires when stake of 0 tokens is attempted.
     * @param owner is the owner of the tokens.
     * @param tokenAdd is the token contract address.
     */
    event DepositZero(address indexed owner, address tokenAdd);

    /**
     * @notice Event fires when withdraw of 0 tokens is attempted.
     * @param owner is the owner of the tokens.
     * @param tokenAdd is the token contract address.
     */
    event WithdrawZero(address indexed owner, address tokenAdd);

    /**
     * @notice Error when trying to access a function without ownership.
     * @param owner is the address of the marketmaker that owns the box.
     */
    error NotBoxOwner(address owner);

    /**
     * @notice Error when trying deposit too large an amount.
     * @param amount is the new balance that violates the max limit.
     */
    error InvalidBalance(uint256 amount);

    function deposit(uint256) external;
    function withdraw(uint256) external;
    function withdrawMax() external;
    function reserveForMarket(uint256) external;
    function returnToOwner(uint256) external;
    function grantVIP(address, uint8) external returns (bool);
    function revokeVIP(address, uint8) external returns (bool);
    function isVIP(address, uint8) external view returns (bool);
    function getOwner() external view returns(address);
    // Auto getters from public vars
    function token() external view returns(address);
    function tokenDecimals() external view returns(uint8);
}
