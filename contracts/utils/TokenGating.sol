// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./TokenValidator.sol";
import "../interfaces/utils/ITokenGating.sol";
import "../libs/TokenAmountValidator.sol";

/**
 * @title  Token Gating
 * @author betBase community
 * @notice An access control contract. It restricts access to otherwise public
 *         methods, by checking user balance of a preset token.
 * @notice This is a util contract for the betBlox protocol.
 */
abstract contract TokenGating is ITokenGating, TokenValidator {
    using TokenAmountValidator for address;

    address public gatingToken; // Any ERC20 token to check balance on
    uint256[3] public presetAmounts; // use to hold preset amount for balance comparison.

    /**
     * @notice Modifier that checks that an address has a min balance of a supplied token.
     * @param owner The owner of the token balance.
     * @param tokenAddress The token to check the availability for.
     * @param amount Is amount to check for.
     */
    modifier requireUserTokenBalance(address owner, address tokenAddress, uint256 amount) {
        _requireHasMinBalance(owner, amount, tokenAddress);
        _;
    }

    /**
     * @notice Modifier that checks that only the msg sender has a min balance.
     * @param amount Is amount to check for.
     */
    modifier hasMinBalance(uint256 amount) {
        _requireHasMinBalance(msg.sender, amount, gatingToken);
        _;
    }

    /**
     * @notice Modifier that checks that only the msg sender has a preset min balance.
     */
    modifier hasMinBalance0() {
        _requireHasMinBalance(msg.sender, presetAmounts[0], gatingToken);
        _;
    }

    /**
     * @notice Modifier that checks that only the msg sender has a preset min balance.
     */
    modifier hasMinBalance1(uint256 amount) {
        _requireHasMinBalance(msg.sender, presetAmounts[1], gatingToken);
        _;
    }

    /**
     * @notice Modifier that checks that only the msg sender has a preset min balance.
     */
    modifier hasMinBalance2(uint256 amount) {
        _requireHasMinBalance(msg.sender, presetAmounts[2], gatingToken);
        _;
    }

    /**
     * @notice Simple constructor, just calls TokenValidator constructor.
     */
    constructor() TokenValidator() {}

    /**
     * @notice Set the token to check balance for.
     * @param inTokenAdd The token to check balance for.
     */
    function setGatingToken(address inTokenAdd) external onlyRole(OPERATION_ADMIN_ROLE) {
        _setGatingToken(inTokenAdd);
    }

    /**
     * @notice Set the preset amounts the to check balance against.
     * @param amount0 Is preset amount 0 to use as balance requirement.
     * @param amount1 Is preset amount 1 to use as balance requirement.
     * @param amount2 Is preset amount 2 to use as balance requirement.
     */
    function setPresetGatingAmounts(
        uint256 amount0,
        uint256 amount1,
        uint256 amount2
    ) external onlyRole(OPERATION_ADMIN_ROLE) {
        _setPresetGatingAmounts(amount0, amount1, amount2);
    }

    function _requireHasMinBalance(address owner, uint256 amount, address tokenAddress) internal view {
        if (tokenAddress == ZERO_ADDRESS) {
            revert BadTokenZero();
        }
        owner.checkBalance(amount, tokenAddress);
    }

    function _setPresetGatingAmounts(uint256 amount0, uint256 amount1, uint256 amount2) internal {
        emit SetGatingAmounts(amount0, amount1, amount2);
        presetAmounts = [amount0, amount1, amount2];
    }

    function _setGatingToken(address inTokenAdd) internal {
        emit SetGatingToken(inTokenAdd, gatingToken);
        gatingToken = inTokenAdd;
    }
}
