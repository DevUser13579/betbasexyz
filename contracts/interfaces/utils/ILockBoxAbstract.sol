// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ILockBoxAbstract {
    /**
     * @notice Event that fires when tokens are locked.
     * @param owner is the token owner that got the tokens locked.
     * @param token is the token contract address
     * @param lockedAmount is the amount locked.
     */
    event TokensLocked(bytes32 indexed owner, address indexed token, uint256 lockedAmount);

    /**
     * @notice Event that fires when tokens are unlocked.
     * @param owner is the token owner that gets the tokens unlocked.
     * @param token is the token contract address
     * @param unlockedAmount is the amount unlocked.
     */
    event TokensUnlocked(bytes32 indexed owner, address indexed token, uint256 unlockedAmount);

    /**
     * Error for token unlock failure,
     * although balance should always be available.
     * Needed `required` but only `available` available.
     * @param owner is the token owner that want to unlock tokens.
     * @param token is the token contract address.
     * @param available balance available.
     * @param required requested amount to unlock.
     */
    error InsufficientLockedTokens(
        bytes32 owner,
        address token,
        uint256 available,
        uint256 required
    );

    function getLockedAmount(address, address) external view returns (uint256);
    function hasLockedAmount(address, address, uint256) external view returns (bool);

    function getLockedAmount(uint256, address) external view returns (uint256);
    function hasLockedAmount(uint256, address, uint256) external view returns (bool);

    function getLockedAmount(bytes32, address) external view returns (uint256);
    function hasLockedAmount(bytes32, address, uint256) external view returns (bool);
}
