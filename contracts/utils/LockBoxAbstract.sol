// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../interfaces/utils/ILockBoxAbstract.sol";

/**
 * @title Lock Box Abstract
 * @author betBase community
 * @notice Abstract contract for storing tokens in a locked state.
 * @notice It is extended in the LockBox contract with external interface and AccessControl.
 * @notice This is a sub contract for the betBlox protocol.
 * @notice Its keeps a list of locked tokens and can own the locked tokens.
 * @notice TokenValidator is AccessHandler, AccessHandler is Initializable.
 */
abstract contract LockBoxAbstract {
    // Owner is represented as a bytes32 value. If supplied as an uint256 it will be converted.
    // An owner ethereum address (20 bytes) will just set least significant bytes (LSB).
    // If the owner is supplied/retrieved as an address value, it must be prepended with 0x00 for 12 MSB.
    // owner => token => amount
    mapping(bytes32 => mapping(address => uint256)) internal lockedTokens;

    /**
     * @notice Gets the users locked amount for a token.
     * @param owner The owner of the balance.
     * @param token The token type.
     * @return uint256 The amount currently locked.
     */
    function getLockedAmount(address owner, address token) public view returns (uint256) {
        return lockedTokens[bytes32(uint256(uint160(owner)))][token];
    }

    /**
     * @notice Checks if user has a locked amount for a token.
     * @param owner The owner of the balance.
     * @param token The token type.
     * @param amount The amount to check.
     * @return bool true if the amount is locked, false if not.
     */
    function hasLockedAmount(address owner, address token, uint256 amount) public view returns (bool) {
        return lockedTokens[bytes32(uint256(uint160(owner)))][token] >= amount;
    }

    /**
     * @notice Gets the users locked amount for a token.
     * @param owner The owner of the balance.
     * @param token The token type.
     * @return uint256 The amount currently locked.
     */
    function getLockedAmount(uint256 owner, address token) public view returns (uint256) {
        return lockedTokens[bytes32(owner)][token];
    }

    /**
     * @notice Checks if user has a locked amount for a token.
     * @param owner The owner of the balance.
     * @param token The token type.
     * @param amount The amount to check.
     * @return bool true if the amount is locked, false if not.
     */
    function hasLockedAmount(uint256 owner, address token, uint256 amount) public view returns (bool) {
        return lockedTokens[bytes32(owner)][token] >= amount;
    }

    /**
     * @notice Gets the users locked amount for a token.
     * @param owner The owner of the balance.
     * @param token The token type.
     * @return uint256 The amount currently locked.
     */
    function getLockedAmount(bytes32 owner, address token) public view returns (uint256) {
        return lockedTokens[owner][token];
    }

    /**
     * @notice Checks if user has a locked amount for a token.
     * @param owner The owner of the balance.
     * @param token The token type.
     * @param amount The amount to check.
     * @return bool true if the amount is locked, false if not.
     */
    function hasLockedAmount(bytes32 owner, address token, uint256 amount) public view returns (bool) {
        return lockedTokens[owner][token] >= amount;
    }

    /**
     * @notice Increases the users locked amount for a token.
     * @param owner The owner to update.
     * @param token The token type to lock in box.
     * @param amount The amount to add.
     */
    function _lock(address owner, address token, uint256 amount) internal {
        _lock(bytes32(uint256(uint160(owner))), token, amount);
    }

    function _lock(uint256 owner, address token, uint256 amount) internal {
        _lock(bytes32(owner), token, amount);
    }

    function _lock(bytes32 owner, address token, uint256 amount) internal {
        if (amount == 0) return;
        lockedTokens[owner][token] += amount;
        emit ILockBoxAbstract.TokensLocked(owner, token, amount);
    }

    /**
     * @notice Decreases the users locked amount.
     * @param owner The owner to update.
     * @param token The token type to unlock.
     * @param amount The amount to unlock.
     */
    function _unlock(address owner, address token, uint256 amount) internal {
        _unlock(bytes32(uint256(uint160(owner))), token, amount);
    }

    function _unlock(uint256 owner, address token, uint256 amount) internal {
        _unlock(bytes32(owner), token, amount);
    }

    function _unlock(bytes32 owner, address token, uint256 amount) internal {
        if (amount == 0) return;
        if (amount > lockedTokens[owner][token]) {
            revert ILockBoxAbstract.InsufficientLockedTokens({
                owner: owner,
                token: token,
                available: lockedTokens[owner][token],
                required: amount
            });
        }
        lockedTokens[owner][token] -= amount;
        emit ILockBoxAbstract.TokensUnlocked(owner, token, amount);
    }

    /**
     * @notice Transfer a lock amount from one owner to another.
     * @param owner The owner to update decrease lock balance for.
     * @param receiver The new owner to receive the transfer amount.
     * @param token The token type to transfer.
     * @param amount The amount to unlock.
     */
    function _transferLock(uint256 owner, uint256 receiver, address token, uint256 amount) internal {
        _unlock(owner, token, amount);
        _lock(receiver, token, amount);
    }

    function _transferLock(address owner, address receiver, address token, uint256 amount) internal {
        _unlock(owner, token, amount);
        _lock(receiver, token, amount);
    }

    function _transferLock(bytes32 owner, bytes32 receiver, address token, uint256 amount) internal {
        _unlock(owner, token, amount);
        _lock(receiver, token, amount);
    }
}
