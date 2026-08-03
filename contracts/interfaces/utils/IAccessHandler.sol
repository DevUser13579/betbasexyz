// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/access/IAccessControl.sol";

interface IAccessHandler is IAccessControl {
    function addAdmin(address) external;
    function removeAdmin(address) external;
    function pause() external;
    function unpause() external;
}
