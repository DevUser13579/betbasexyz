// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./ILockBoxAbstract.sol";

interface ILockBox {
    function lockAmount(address, address, uint256) external;
    function unlockAmount(address, address, uint256) external;
    function unlockAmountTo(address, address, address, uint256) external;
    function transferLockAmount(address, address, address, uint256) external;

    function lockAmount(uint256, address, uint256) external;
    function unlockAmount(uint256, address, uint256) external;
    function unlockAmountTo(uint256, address, address, uint256) external;
    function transferLockAmount(uint256, uint256, address, uint256) external;

    function lockAmount(bytes32, address, uint256) external;
    function unlockAmount(bytes32, address, uint256) external;
    function unlockAmountTo(bytes32, address, address, uint256) external;
    function transferLockAmount(bytes32, bytes32, address, uint256) external;
}
