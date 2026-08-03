// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../interfaces/utils/ITokenValidator.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

enum TokenAvailability {
    InsufficientBalance,
    InsufficientAllowance,
    OK
}

/**
 * @title TokenAmountValidator
 * @author betBase community
 * @notice Lib to help with checking token balances, allowance etc.
 */
library TokenAmountValidator {
    address internal constant ZERO_ADDRESS = address(0);

    /**
     * @notice Error for Insufficient token balance for an operation.
     * @notice Needed `required` but only `available` available.
     * @param owner is the address that owns the tokens.
     * @param tokenAdd is the token contract address.
     * @param available balance available.
     * @param required requested amount to transfer.
     */
    error InsufficientBalance(
        address owner,
        address tokenAdd,
        uint256 available,
        uint256 required
    );

    /**
     * @notice Error for Insufficient token allowance for an operation.
     * @notice Needed `required` but only `available` available.
     * @param owner is the address that owns the tokens.
     * @param receiver is the address to receive the allowance.
     * @param tokenAdd is the token contract address.
     * @param available allowance available.
     * @param required required amount.
     */
    error InsufficientAllowance(
        address owner,
        address receiver,
        address tokenAdd,
        uint256 available,
        uint256 required
    );

    /**
     * @notice Checks an address balance and allowance for a given amount.
     * @param owner The owner of the token balance and allowance.
     * @param amount Is amount to check for.
     * @param tokenAddress The token to check the availability for.
     * @param receiver The address to check allowance for.
     */
    function checkAllowanceAndBalance(address owner, uint256 amount, address tokenAddress, address receiver)
        internal
        view
    {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.allowance(owner, receiver);
        if (balance < amount) {
            revert InsufficientAllowance({
                owner: owner,
                receiver: receiver,
                tokenAdd: tokenAddress,
                available: balance,
                required: amount
            });
        }
        balance = token.balanceOf(owner);
        if (balance < amount) {
            revert InsufficientBalance({
                owner: owner,
                tokenAdd: tokenAddress,
                available: balance,
                required: amount
            });
        }
    }

    /**
     * @notice Checks an address balance for a given amount.
     * @param owner The owner of the token balance.
     * @param amount Is amount to check for.
     * @param tokenAddress The token to check the availability for.
     */
    function checkBalance(address owner, uint256 amount, address tokenAddress) internal view {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(owner);
        if (balance < amount) {
            revert InsufficientBalance({
                owner: owner,
                tokenAdd: tokenAddress,
                available: balance,
                required: amount
            });
        }
    }
}
