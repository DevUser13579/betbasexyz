// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ITokenValidator {
    /**
     * Error for using a zero address token.
     */
    error BadTokenZero();

    /**
     * Error for using a address that is not a token (not a contract).
     * @param tokenAdd is the address of the token.
     */
    error InvalidToken(address tokenAdd);

    /**
     * Error for using a not allowed token.
     * @param tokenAdd is the address of the token.
     */
    error TokenNotAllowed(address tokenAdd);

    function addToken(address) external;
    function removeToken(address) external;
    function enableValidation() external;
    function disableValidation() external;
    function isAllowedToken(address) external view returns (bool);
}
