// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../constants/globals.sol";
import "../interfaces/utils/IFeeHandler.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Fee Handler
 * @author betBase community
 * @notice Simple contract for handling fees.
 * @notice This is a utility contract for the betBlox protocol, meant for extending.
 * @notice AccessHandler is Initializable.
 */
abstract contract FeeHandler is IFeeHandler, AccessControl {
    uint16 public maxFeePermilleToMM;
    uint16 public feePermilleBettor;
    uint16 public feePermilleOwnMM;
    uint16 public feePermilleOracleMM;
    address public feeReceiver;
    address internal _token; // Address of the token used for betting and fees.

    /**
     * @notice Setter to change the referenced receiver address.
     * @param inFeeReceiver Is the new address.
     */
    function setFeeReceiver(address inFeeReceiver) external onlyRole(OPERATION_ADMIN_ROLE) {
        _setFeeReceiver(inFeeReceiver);
    }

    /**
     * @notice Sets the rate of fees to charge from bettors.
     * @param inFeePermille is the fee permille to charge.
     */
    function setFeeBettor(uint16 inFeePermille) external onlyRole(OPERATION_ADMIN_ROLE) {
        _setFeeBettor(inFeePermille);
    }

    /**
     * @notice Sets the rate of fees to charge from marketmaker for own events.
     * @param inFeePermille is the fee permille to charge.
     */
    function setFeeOwnMM(uint16 inFeePermille) external onlyRole(OPERATION_ADMIN_ROLE) {
        _setFeeOwnMM(inFeePermille);
    }

    /**
     * @notice Sets the rate of fees to charge from marketmaker for Oracle events.
     * @param inFeePermille is the fee permille to charge.
     */
    function setFeeOracleMM(uint16 inFeePermille) external onlyRole(OPERATION_ADMIN_ROLE) {
        _setFeeOracleMM(inFeePermille);
    }

    /**
     * @notice Sets the max win fee rate, the marketmaker can charge from bettors.
     * @param inFeePermille is the max fee permille to charge.
     */
    function setMaxFeeToMM(uint16 inFeePermille) external onlyRole(OPERATION_ADMIN_ROLE) {
        _setMaxFeeToMM(inFeePermille);
    }

    /**
     * @notice Initializes this contract with fees details.
     * @param inFeeReceiver is the fee receiver address.
     * @param inFeePermilleBettor is the fee permille to charge from bettors.
     * @param inFeePermilleOracleMM is the fee permille to charge for marketmakers on Oracle events.
     * @param inFeePermilleOwnMM is the fee permille to charge for marketmakers on own events.
     * @param inMaxFeePermille is the max fee permille to charge from bettors to marketmakers.
     */
    function _initFees(
        address inFeeReceiver,
        uint16 inFeePermilleBettor,
        uint16 inFeePermilleOracleMM,
        uint16 inFeePermilleOwnMM,
        uint16 inMaxFeePermille
    ) internal {
        if (inFeeReceiver != ZERO_ADDRESS) {
            _setFeeReceiver(inFeeReceiver);
            _setFeeBettor(inFeePermilleBettor);
            _setFeeOracleMM(inFeePermilleOracleMM);
            _setFeeOwnMM(inFeePermilleOwnMM);
        }
        _setMaxFeeToMM(inMaxFeePermille);
    }

    /**
     * @notice Pays fees to the allocated handlers.
     * @param inFrom is the address from where to transfer the fee.
     * @param inReceiver is the address that receives the fee.
     * @param inContributor is the address that contributes the fee.
     * @param inFee is the fee amount.
     */
    function _payFee(
        address inFrom,
        address inReceiver,
        address inContributor,
        uint256 inFee
    ) internal {
        // Transfer the fee to the receiver
        if (inFrom == address(this)) IERC20(_token).transfer(inReceiver, inFee);
        else IERC20(_token).transferFrom(inFrom, inReceiver, inFee);

        emit FeePaid(inContributor, inReceiver, inFee);
    }

    /**
     * @notice Check the win fee rate, the marketmaker charges from bettors.
     * @notice Error is emitted if the fee is not allowed.
     * @param inFeePermille is the fee permille to check.
     */
    function _validateFeeToMM(uint16 inFeePermille) internal view {
        if (maxFeePermilleToMM != 0 && inFeePermille > maxFeePermilleToMM)
            revert InvalidFee({feePermille: inFeePermille, maxValue: maxFeePermilleToMM});
        if (inFeePermille > MAX_PERMILLE)
            revert InvalidFee({feePermille: inFeePermille, maxValue: MAX_PERMILLE});
    }

    /**
     * @notice Sets the rate of fees to charge from bettors.
     * @param inFeePermille is the fee permille to charge.
     */
    function _setFeeBettor(uint16 inFeePermille) internal {
        if (inFeePermille > MAX_PERMILLE) revert InvalidFee({feePermille: inFeePermille, maxValue: MAX_PERMILLE});

        emit FeeBettorSet(inFeePermille, feePermilleBettor);
        feePermilleBettor = inFeePermille;
    }

    /**
     * @notice Sets the rate of fees to charge from marketmaker for own events.
     * @param inFeePermille is the fee permille to charge.
     */
    function _setFeeOwnMM(uint16 inFeePermille) internal {
        if (inFeePermille > MAX_PERMILLE) revert InvalidFee({feePermille: inFeePermille, maxValue: MAX_PERMILLE});

        emit FeeOwnMMSet(inFeePermille, feePermilleBettor);
        feePermilleOwnMM = inFeePermille;
    }

    /**
     * @notice Sets the rate of fees to charge from marketmaker for Oracle events.
     * @param inFeePermille is the fee permille to charge.
     */
    function _setFeeOracleMM(uint16 inFeePermille) internal {
        if (inFeePermille > MAX_PERMILLE) revert InvalidFee({feePermille: inFeePermille, maxValue: MAX_PERMILLE});

        emit FeeOracleMMSet(inFeePermille, feePermilleBettor);
        feePermilleOracleMM = inFeePermille;
    }

    /**
     * @notice Sets the max win fee rate, the marketmaker can charge from bettors.
     * @param inFeePermille is the max fee permille to charge.
     */
    function _setMaxFeeToMM(uint16 inFeePermille) internal {
        if (inFeePermille > MAX_PERMILLE) revert InvalidFee({feePermille: inFeePermille, maxValue: MAX_PERMILLE});

        emit MaxFeeToMMSet(inFeePermille, maxFeePermilleToMM);
        maxFeePermilleToMM = inFeePermille;
    }

    /**
     * @notice Setter to change the referenced receiver address.
     * @param inFeeReceiver Is the new address.
     */
    function _setFeeReceiver(address inFeeReceiver) internal {
        if (inFeeReceiver == address(0)) revert InvalidFeeReceiver();

        emit FeeReceiverSet(inFeeReceiver, feeReceiver);
        feeReceiver = inFeeReceiver;
    }

    /**
     * @notice Setter to change the referenced currency Token contract.
     * @param inToken The Token contract address.
     */
    function _setToken(address inToken) internal {
        emit SetToken(inToken);
        _token = inToken;
    }
}
