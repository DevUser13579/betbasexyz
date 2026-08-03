// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../constants/globals.sol";
import "../interfaces/utils/IAccessHandler.sol";
import "./BaseInitializer.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Access Handler
 * @author betBase community
 * @notice An access control contract. It restricts access to otherwise public
 *         methods, by checking for assigned roles. its meant to be extended
 *         and holds all the predefined role type for the derrived contracts.
 * @notice This is a util contract for the betBlox protocol.
 */
abstract contract AccessHandler is IAccessHandler, BaseInitializer, AccessControl, Pausable {
    /**
     * @notice Simple constructor, just sets the admin.
     * Allows for AccessHandler to be inherited by non-upgradeable contracts
     * that are normally deployed, with a contructor call.
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATION_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /**
     * @notice Adds another admin.
     * @param newAdmin is the addresse of the new admin.
     */
    function addAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
    }

    /**
     * @notice Removes an admin.
     * @param inAdmin is the addresse of the admin to remove.
     */
    function removeAdmin(address inAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // We want at least 1 admin, so admins cannot accidentally renounce their own role (by this method).
        if (inAdmin != _msgSender())
            _revokeRole(DEFAULT_ADMIN_ROLE, inAdmin);
    }

    /**
     * @notice Puts the contract in pause state, for emergency control.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Puts the contract in operational state, after being paused.
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
