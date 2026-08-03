// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../constants/globals.sol";
import "../interfaces/utils/ITokenValidator.sol";
import "./AccessHandler.sol";

/**
 * @title  Token Validator
 * @author betBase community
 * @notice An access control contract. It restricts access to otherwise public
 *         methods, by checking for assigned roles to tokens. Some other
 *         token validations are also perform (contract and 0 address).
 * @notice This is a util contract for the betBlox protocol.
 */
abstract contract TokenValidator is ITokenValidator, AccessHandler {
    // address internal constant ZERO_ADDRESS = address(0);

    /**
     * @notice Modifier that checks that only allowed tokens are used.
     * @param inToken The token to verify.
     */
    modifier onlyAllowedToken(address inToken) {
        if (!getInitialized()) revert NotInitialized();
        if (inToken == ZERO_ADDRESS) revert BadTokenZero();
        if (!isERC20(inToken)) revert InvalidToken({tokenAdd: inToken});
        if (_enabledValidation() && !hasRole(TOKEN_ROLE, inToken)) revert TokenNotAllowed({tokenAdd: inToken});
        _;
    }

    /**
     * @notice Simple constructor, just calls AccessHandler constructor.
     */
    constructor() AccessHandler() {}

    /**
     * @notice Add a token to the allowed list.
     * @param inTokenAdd The token to add to the allowed list.
     */
    function addToken(address inTokenAdd) external onlyRole(OPERATION_ADMIN_ROLE) {
        // We are only interested in the key token in this case,
        // but the value cannot be the 0 addresse
        _addToken(inTokenAdd);
    }

    /**
     * @notice Remove an ERC20 token key from the list.
     * @param inTokenAdd The token to remove from the allowed list.
     */
    function removeToken(address inTokenAdd) external onlyRole(OPERATION_ADMIN_ROLE) {
        // Clear the allowed role list entry.
        _revokeRole(TOKEN_ROLE, inTokenAdd);
    }

    /**
     * @notice Enable the token validation.
     */
    function enableValidation() external onlyRole(OPERATION_ADMIN_ROLE) {
        // Enable validation, if it isn't already.
        _revokeRole(TOKEN_ROLE, ZERO_ADDRESS);
    }

    /**
     * @notice Disable the token validation.
     */
    function disableValidation() external onlyRole(OPERATION_ADMIN_ROLE) {
        // Disable validation, if it isn't already.
        _grantRole(TOKEN_ROLE, ZERO_ADDRESS);
    }

    /**
     * @notice Checks if an allowed token address is supplied.
     * @param inToken The token to check.
     * @return bool true if the token is allowed, false if not.
     */
    function isAllowedToken(address inToken) external view returns (bool) {
        if (!getInitialized()) {
            revert NotInitialized();
        }
        return _isAllowedToken(inToken);
    }

    /**
     * @notice Check if validation is enabled, by checking if ZERO_ADDRESS has the role.
     */
    function _enabledValidation() internal view returns (bool) {
        return !hasRole(TOKEN_ROLE, ZERO_ADDRESS);
    }

    /**
     * @notice Add an ERC20 token to the list of allowed tokens.
     * @param inToken The token address as key in the allowed list.
     */
    function _addToken(address inToken) internal {
        if (inToken == ZERO_ADDRESS) {
            revert BadTokenZero();
        }
        if (!isERC20(inToken)) {
            revert InvalidToken({tokenAdd: inToken});
        }

        // Add the token to the role list of accepted tokens.
        _grantRole(TOKEN_ROLE, inToken);
        // Enable validation, if it isn't already.
        _revokeRole(TOKEN_ROLE, ZERO_ADDRESS);
    }

    /**
     * @notice Checks if an allowed token address is supplied.
     * @param inToken The token to check.
     * @return bool true if the token is allowed, false if not.
     */
    function _isAllowedToken(address inToken) internal view returns (bool) {
        if (inToken == ZERO_ADDRESS) {
            return false;
        }
        if (!isERC20(inToken)) {
            return false;
        }
        if (_enabledValidation()) {
            return hasRole(TOKEN_ROLE, inToken);
        }
        return true;
    }

    /**
     * @notice Check if an addresse is for an (ERC20 token) contract.
     * @param inToken The token address to check.
     * @return bool true if the address is compliant, false if not.
     */
    function isERC20(address inToken) internal view returns (bool) {
        // Since OZ ERC20 does not implement EIP165 or similar, we just make a contract code check.
        // In contracts v5.0 Address.isContract() is removed as well.
        uint32 size;
        assembly {
            size := extcodesize(inToken)
        }
        return (size > 0);
    }
}
