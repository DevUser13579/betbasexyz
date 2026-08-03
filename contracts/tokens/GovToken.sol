// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../interfaces/tokens/IGovToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Governance Token (GOV)
 * @author betBase community
 * @notice Simple ERC20 Token class used to account for governance.
 * @notice It is protected from minting, but burn and transfer is available.
 * @notice This is a sub contract for the DaoMain app.
 */
contract GovToken is IGovToken, ERC20 {
    /**
     * @notice Simple constructor, just sets the admin and inits token.
     * @param initialSupply is the initial amount of tokens to mint.
     * @param inName is the ERC20 token name.
     * @param inSymbol is the ERC20 token symbol.
     */
    constructor(uint256 initialSupply, string memory inName, string memory inSymbol ) ERC20(inName, inSymbol) {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Destroys `amount` tokens from the caller.
     * @param amount is the amount of tokens to burn.
     * @notice See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual {
        _burn(msg.sender, amount);
    }
}
