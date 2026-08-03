// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./IAccessHandler.sol";

interface ITokenGating is IAccessHandler {
    /**
     * @notice Event fires when new preset amounts are set.
     * @param amount0 Is preset amount 0 to use as balance requirement.
     * @param amount1 Is preset amount 1 to use as balance requirement.
     * @param amount2 Is preset amount 2 to use as balance requirement.
     */
    event SetGatingAmounts(uint256 amount0, uint256 amount1, uint256 amount2);

    /**
     * @notice Event that fires when the gating token is set.
     * @param newAdd is the new address.
     * @param oldAdd is the previous address.
     */
    event SetGatingToken(address newAdd, address oldAdd);

    function setGatingToken(address) external;
    function setPresetGatingAmounts(uint256, uint256, uint256) external;
    function gatingToken() external view  returns (address);
    function presetAmounts(uint256) external view returns (uint256);
}
