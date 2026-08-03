// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../interfaces/utils/ILockBox.sol";
import "./LockBoxAbstract.sol";
import "./TokenValidator.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Lock Box
 * @author betBase community
 * @notice Simple contract for storing tokens in a locked state.
 * @notice This is a sub contract for the betBlox protocol.
 * @notice Its keeps a list of locked tokens and can own the locked tokens.
 * @notice TokenValidator is AccessHandler, AccessHandler is Initializable.
 */
contract LockBox is ILockBox, LockBoxAbstract, TokenValidator {

    /**
     * @notice Default constructor.
     */
    constructor() {}

    /**
     * @notice Init function to call if this is deployed instead of extended.
     * @notice Init withut setting a token will disable token validation.
     */
    function initBox() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _initBox();
    }

    /**
     * @notice Init function to call if this is deployed instead of extended.
     * @notice This init will set an allowed token and enable token validation.
     */
    function initBoxWithToken(address inToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addToken(inToken);
        _initBox();
    }

    /**
     * @notice Increases the users locked amount for a token.
     * @param owner The owner to update.
     * @param token The token type to lock in box.
     * @param amount The amount to add.
     */
    function lockAmount(
        address owner,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _lock(owner, token, amount);
    }

    /**
     * @notice Decreases the users locked amount.
     * @param owner The owner to update.
     * @param token The token type to unlock.
     * @param amount The amount to unlock.
     */
    function unlockAmount(
        address owner,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _unlock(owner, token, amount);
    }

    /**
     * @notice Decreases an owners locked amount and sets allowance to other.
     *         This assumes tokens are owned by the box and sets allowance.
     * @param owner The owner to update.
     * @param to The receiver of the token allowance.
     * @param token The token type to unlock.
     * @param amount The amount to unlock and allow.
     */
    function unlockAmountTo(
        address owner,
        address to,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        // We increase the allowance instead of setting it fixed,
        // although allowances for the box should be spend immediately.
        uint256 allowance = IERC20(token).allowance(address(this), to);
        allowance += amount;
        _unlock(owner, token, amount);

        IERC20(token).approve(to, allowance);
    }

    /**
     * @notice Transfer a lock amount form one owner to another.
     * @param owner The owner to update decrease lock balance for.
     * @param receiver The new owner to receive the transfer amount.
     * @param token The token type to transfer.
     * @param amount The amount to unlock.
     */
    function transferLockAmount(
        address owner,
        address receiver,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _transferLock(owner, receiver, token, amount);
    }

    /**
     * @notice Increases the users locked amount for a token.
     * @param owner The owner to update.
     * @param token The token type to lock in box.
     * @param amount The amount to add.
     */
    function lockAmount(
        uint256 owner,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _lock(owner, token, amount);
    }

    /**
     * @notice Decreases the users locked amount.
     * @param owner The owner to update.
     * @param token The token type to unlock.
     * @param amount The amount to unlock.
     */
    function unlockAmount(
        uint256 owner,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _unlock(owner, token, amount);
    }

    /**
     * @notice Decreases an owners locked amount and sets allowance to other.
     *         This assumes tokens are owned by the box and sets allowance.
     * @param owner The owner to update.
     * @param to The receiver of the token allowance.
     * @param token The token type to unlock.
     * @param amount The amount to unlock and allow.
     */
    function unlockAmountTo(
        uint256 owner,
        address to,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        // We increase the allowance instead of setting it fixed,
        // although allowances for the box should be spend immediately.
        uint256 allowance = IERC20(token).allowance(address(this), to);
        allowance += amount;
        _unlock(owner, token, amount);

        IERC20(token).approve(to, allowance);
    }

    /**
     * @notice Transfer a lock amount form one owner to another.
     * @param owner The owner to update decrease lock balance for.
     * @param receiver The new owner to receive the transfer amount.
     * @param token The token type to transfer.
     * @param amount The amount to unlock.
     */
    function transferLockAmount(
        uint256 owner,
        uint256 receiver,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _transferLock(owner, receiver, token, amount);
    }

    /**
     * @notice Increases the users locked amount for a token.
     * @param owner The owner to update.
     * @param token The token type to lock in box.
     * @param amount The amount to add.
     */
    function lockAmount(
        bytes32 owner,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _lock(owner, token, amount);
    }

    /**
     * @notice Decreases the users locked amount.
     * @param owner The owner to update.
     * @param token The token type to unlock.
     * @param amount The amount to unlock.
     */
    function unlockAmount(
        bytes32 owner,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _unlock(owner, token, amount);
    }

    /**
     * @notice Decreases an owners locked amount and sets allowance to other.
     *         This assumes tokens are owned by the box and sets allowance.
     * @param owner The owner to update.
     * @param to The receiver of the token allowance.
     * @param token The token type to unlock.
     * @param amount The amount to unlock and allow.
     */
    function unlockAmountTo(
        bytes32 owner,
        address to,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        // We increase the allowance instead of setting it fixed,
        // although allowances for the box should be spend immediately.
        uint256 allowance = IERC20(token).allowance(address(this), to);
        allowance += amount;
        _unlock(owner, token, amount);

        IERC20(token).approve(to, allowance);
    }

    /**
     * @notice Transfer a lock amount form one owner to another.
     * @param owner The owner to update decrease lock balance for.
     * @param receiver The new owner to receive the transfer amount.
     * @param token The token type to transfer.
     * @param amount The amount to unlock.
     */
    function transferLockAmount(
        bytes32 owner,
        bytes32 receiver,
        address token,
        uint256 amount
    ) external onlyRole(LOCKBOX_ROLE) onlyAllowedToken(token) {
        _transferLock(owner, receiver, token, amount);
    }

    /**
     * @notice Init function that initializes the AccessHandler.
     */
    function _initBox() internal {
        BaseInitializer.initialize();
    }
}
