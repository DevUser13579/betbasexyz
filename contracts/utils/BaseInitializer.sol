// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract BaseInitializer is Initializable {

    /**
     * Error for call to a contract that is not yet initialized.
     */
    error NotInitialized();

    /**
     * Error for call to a contract that is already initialized.
     */
    error AlreadyInitialized();

    /**
     * @notice Throws if this contract has not been initialized.
     */
    modifier isInitialized() {
        if (!getInitialized()) revert NotInitialized();
        _;
    }

    /**
     * @notice Get the state of initialization.
     * @return bool true if initialized.
     */
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /**
     * @notice Initialize and remember this state to avoid repeating.
     */
    function initialize() internal virtual initializer {}

    /**
     * @notice Get the state of initialization.
     * @return bool true if initialized.
     */
    function getInitialized() internal view returns (bool) {
        return _getInitializedVersion() != 0 && !_isInitializing();
    }
}