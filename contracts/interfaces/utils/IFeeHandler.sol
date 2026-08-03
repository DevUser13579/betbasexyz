// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IFeeHandler {
    /**
     * @notice Event that fires when the token is set.
     * @param add is the new address.
     */
    event SetToken(address add);

    /**
     * @notice Event fires when marketmaker fee rate for own events is set.
     * @param feePermille is the fee permille to charge.
     * @param oldValue is the previous fee rate.
     */
    event FeeOwnMMSet(uint16 feePermille, uint16 oldValue);

    /**
     * @notice Event fires when marketmaker fee rate for Oracle events is set.
     * @param feePermille is the fee permille to charge.
     * @param oldValue is the previous fee rate.
     */
    event FeeOracleMMSet(uint16 feePermille, uint16 oldValue);

    /**
     * @notice Event fires when bettor fee rate is set.
     * @param feePermille is the fee permille to charge.
     * @param oldValue is the previous fee rate.
     */
    event FeeBettorSet(uint16 feePermille, uint16 oldValue);

    /**
     * @notice Event fires when bettor to marketmaker max fee rate is set.
     * @param feePermille is the max fee permille to set.
     * @param oldValue is the previous max fee rate.
     */
    event MaxFeeToMMSet(uint16 feePermille, uint16 oldValue);

    /**
     * @notice Event fires when fee receiver is set.
     * @param newAdd is the new address.
     * @param oldAdd is the old address.
     */
    event FeeReceiverSet(address newAdd, address oldAdd);

    /**
     * @notice Event fires when a fee is paid.
     * @param from is the address of the contributor.
     * @param to is the receiver of the fee.
     * @param amount is the size of the fee.
     */
    event FeePaid(address from, address to, uint256 amount);

    /**
     * @notice Error is thrown when invalid fees are set.
     * @param feePermille is the fee permille requested.
     * @param maxValue is the max fee permille to charge.
     */
    error InvalidFee(uint16 feePermille, uint16 maxValue);

    /**
     * @notice Error is thrown when fees are assigned to address 0.
     */
    error InvalidFeeReceiver();

    function setFeeReceiver(address) external;
    function setFeeBettor(uint16) external;
    function setFeeOracleMM(uint16) external;
    function setFeeOwnMM(uint16) external;
    function setMaxFeeToMM(uint16) external;
    function maxFeePermilleToMM() external view returns (uint16);
    function feePermilleBettor() external view returns (uint16);
    function feePermilleOwnMM() external view returns (uint16);
    function feePermilleOracleMM() external view returns (uint16);
    function feeReceiver() external view returns (address);
}
