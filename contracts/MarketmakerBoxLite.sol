// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./utils/LockBoxAbstract.sol";
import "./utils/AccessHandler.sol";
import "./interfaces/IMarketmakerBox.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./libs/TokenAmountValidator.sol";

/**
 * @title Marketmaker Box Lightweight
 * @author betBase community
 * @notice This is the Marketmaker Box, that offers deposit func. It is designed to operate
 *         on a single token only, set at init.
 * @notice Tokens are deposited by marketmakers for easier access, when cretaing markets.
 * @notice Tokens are put in the Lockbox, and the Markethandler/ParlayMarketHandler contracts can use it without approval.
 * @notice The tokens can be withdrawn, if not reserved for markets.
 * @notice MarketmakerBoxLite is LockBoxAbstract (no external lock/unlock functions).
 * @notice AccessHandler is Initializable.
 */
contract MarketmakerBoxLite is LockBoxAbstract, AccessHandler, IMarketmakerBox {
    using TokenAmountValidator for address;

    address public token; // Currency token of the box
    uint8 public tokenDecimals; // Decimals of the token, used to restrict to large amounts
    address private _boxOwner; // Owner of the box
    address private _betBox; // Address of the bet box, where all tokens are locked, when reserved for markets.

    /**
     * @dev Throws if called by any account other than the owner of an event.
     */
    modifier onlyOwner() {
        if (msg.sender != _boxOwner) revert NotBoxOwner(_boxOwner);
        _;
    }

    /**
     * @notice Default Constructor.
     */
    constructor() AccessHandler() {}

    /**
     * @notice Initializes this contract with reference to other contracts.
     * @param inOwner The owner of this box.
     * @param inToken The Token handled by this box.
     * @param inBetBox The external box for tokens invested in markets.
     */
    function init(address inOwner, address inToken, address inBetBox) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _init(inOwner, inToken, inBetBox);
    }

    /**
     * @notice Increases the owners deposited amount of tokens.
     * @param inAmount The amount to deposit.
     */
    function deposit(uint256 inAmount) external whenNotPaused onlyOwner {
        if (inAmount == 0) {
            emit DepositZero(_boxOwner, token);
            return;
        }
        _boxOwner.checkAllowanceAndBalance(inAmount, token, address(this));
        _deposit(inAmount);
    }

    /**
     * @notice Decreases the owners amount of deposit tokens.
     * @param inAmount The amount to withdraw.
     */
    function withdraw(uint256 inAmount) external whenNotPaused onlyOwner {
        _withdraw(inAmount);
    }

    /**
     * @notice Let the owner withdraw all tokens, excluding the amount locket in markets.
     */
    function withdrawMax() external whenNotPaused onlyOwner {
        uint256 ownerBalance = getLockedAmount(_boxOwner, token);
        _withdraw(ownerBalance);
    }

    /**
     * @notice Let a handler take an amount and reserve it for a market, by transfering to the betbox.
     * @notice The call is made by a MarketHandler contract, that is assigned the LockBox role.
     * @notice The MarketHandler contract must additionally make sure to update the lock status of the betbox.
     * @param inAmount The amount of tokens to reassign.
     */
    function reserveForMarket(uint256 inAmount) external onlyRole(MARKETS_ROLE) {
        _unlock(_boxOwner, token, inAmount);
        IERC20(token).transfer(_betBox, inAmount);
    }

    /**
     * @notice Let a handler return and lock an amount, that was reserved for a market, by transfering from the BetBox.
     * @notice The call is made by a MarketHandler contract, that is assigned the LockBox role.
     * @notice The MarketHandler contract must prior to this call, make the amount available for transfer.
     * @param inAmount The amount of tokens to reassign.
     */
    function returnToOwner(uint256 inAmount) external onlyRole(MARKETS_ROLE) {
        IERC20(token).transferFrom(_betBox, address(this), inAmount);
        _lock(_boxOwner, token, inAmount);
    }

    /**
     * @notice Grant a VIP role to an address. There are 254 VIP roles, represented by a calculated hash.
     * @param inAddress is the address to receive the role.
     * @param inGroup is a number from 1 to 254, that is used to calculate the role hash.
     * @return bool true if the role is granted, false if not.
     */
    function grantVIP(address inAddress, uint8 inGroup) external onlyOwner returns (bool) {
        if (inGroup == 0 || inGroup == 255) return false;
        bytes32 role = keccak256(abi.encode(_boxOwner, inGroup));
        return _grantRole(role, inAddress);
    }

    /**
     * @notice Revoke a VIP role from an address. There are 254 VIP roles, represented by a calculated hash.
     * @param inAddress is the address to lose the role.
     * @param inGroup is a number from 1 to 254, that is used to calculate the role hash.
     * @return bool true if the role is revoked, false if not.
     */
    function revokeVIP(address inAddress, uint8 inGroup) external onlyOwner returns (bool) {
        bytes32 role = keccak256(abi.encode(_boxOwner, inGroup));
        return _revokeRole(role, inAddress);
    }

    /**
     * @notice Check if an address has been granted a specific one of 254 VIP roles.
     * @param inAddress is the address to check.
     * @param inGroup is a number from 1 to 254, that is used to calculate the role hash.
     * @return bool true if the role is granted, false if not.
     */
    function isVIP(address inAddress, uint8 inGroup) external view returns (bool) {
        bytes32 role = keccak256(abi.encode(_boxOwner, inGroup));
        return hasRole(role, inAddress);
    }

    /**
     * @notice Getter function for the contract owner.
     * @return address the owners wallet address.
     */
    function getOwner() external view returns (address) {
        return _boxOwner;
    }

    /**
     * @notice Initializes this contract with reference to other contracts.
     * @param inOwner The owner of this box.
     * @param inToken The Token handled by this box.
     * @param inBetBox The external box for tokens invested in markets.
     */
    function _init(address inOwner, address inToken, address inBetBox) internal {
        _boxOwner = inOwner;
        emit SetToken(inToken);
        token = inToken;
        tokenDecimals = IERC20Metadata(inToken).decimals();
        emit SetBetBox(inBetBox);
        _betBox = inBetBox;
        // Grant the owner the admin roles for this box.
        _grantRole(OPERATION_ADMIN_ROLE, _boxOwner);
        _grantRole(PAUSER_ROLE, _boxOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, _boxOwner);
        BaseInitializer.initialize();
    }

    /**
     * @notice Withdraw by unlocking and transfering tokens to the owner.
     * @param inAmount The amount of tokens to return.
     */
    function _withdraw(uint256 inAmount) private {
        if (inAmount == 0) {
            emit WithdrawZero(_boxOwner, token);
            return;
        }
        _unlock(_boxOwner, token, inAmount);
        // Return the deposited tokens
        IERC20(token).transfer(_boxOwner, inAmount);
        emit TokensWithdrawn(_boxOwner, token, inAmount);
    }

    /**
     * @notice Increases the owners amount of deposited tokens.
     * @param inAmount The amount to deposit.
     */
    function _deposit(uint256 inAmount) private {
        uint256 newBalance = inAmount + getLockedAmount(_boxOwner, token);
        if (newBalance > MAX_BALANCE * 10**tokenDecimals)
            revert InvalidBalance(newBalance);

        IERC20(token).transferFrom(_boxOwner, address(this), inAmount);
        _lock(_boxOwner, token, inAmount);
        emit TokensDeposited(_boxOwner, token, inAmount);
    }
}
