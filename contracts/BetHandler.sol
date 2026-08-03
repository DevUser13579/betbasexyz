// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./interfaces/IBetHandler.sol";
import "./interfaces/IMarketHandler.sol";
import "./interfaces/utils/ILockBox.sol";
import "./utils/AccessHandler.sol";
import "./libs/TokenAmountValidator.sol";
import "./constants/markets.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Bet Handling
 * @author betBase community
 * @notice This is the contract for handling bets. It communicates with the Market Handler for adding bets to markets.
 * @notice BetHandler is AccessHandler is Initializable.
 */
contract BetHandler is AccessHandler, IBetHandler {
    using TokenAmountValidator for address;

    // bet hash => bet data
    mapping(bytes32 => BetData) public bets;
    // bet hash => settled status: true or false
    mapping(bytes32 => bool) public betSettled;
    // bet owner => bet agent
    mapping(address => address) private _betAgents;
    address public token; // Currency token for bets
    uint8 public tokenDecimals; // Decimals of the token, used to restrict too large amounts
    IMarketHandler private _marketHandler; // The MarketHandler contract, where markets for the bets are handled.
    address private _betBox; // Address of the bet box, where all tokens are locked, when reserved for markets.

    /**
     * @notice Default Constructor.
     */
    constructor() AccessHandler() {}

    /**
     * @notice Initializes this contract with reference to other contracts.
     * @param inToken The Token used for betting.
     * @param inMarketHandler The MarketHandler contract address.
     * @param inBetBox The external box for tokens invested in bets.
     */
    function init(address inToken, address inMarketHandler, address inBetBox) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _init(inToken, inMarketHandler, inBetBox);
    }

    /**
     * @notice Setter to change the bet agent of a bettor.
     * @param inBetAgent The new agent address, zero address if none.
     */
    function setBetAgent(address inBetAgent) external {
        emit BetAgentSet(msg.sender, inBetAgent);
        _betAgents[msg.sender] = inBetAgent;
    }

    /**
     * @notice Adds a regular bet to a market on behalf of the caller, based on a market hash and bet data.
     * @notice Error is emitted if the bet is not allowed, event if success.
     * @param marketHash is the hash that uniquely identifies the market.
     * @param betAmount is the amount of tokens the bettor is betting (backing) on the market.
     * @param odds is the odds accepted for this bet, in decimal-odds format (multiplied by ODDS_PRECISION).
     * @param outcomeId is a number from 0 - 65535 to define the outcome, as seen from the bettor.
     */
    function addBet(bytes32 marketHash, uint256 betAmount, uint256 odds, uint16 outcomeId) external whenNotPaused {
        _addBet(marketHash, msg.sender, betAmount, BetType.Agent, odds, outcomeId);
    }

    /**
     * @notice Adds a bet to a market on behalf of another, based on a market hash and bet data.
     * @notice Error is emitted if the bet is not allowed, event if success.
     * @notice Restrictions are made based on the _betAgents table, so only assigned agents can make the bet.
     * @param marketHash is the hash that uniquely identifies the market.
     * @param bettor is the wallet address of the bettor (new bet owner).
     * @param betAmount is the amount of tokens the bettor is betting (backing) on the market.
     * @param odds is the odds accepted for this bet, in decimal-odds format (multiplied by ODDS_PRECISION).
     * @param outcomeId is a number from 0 - 65535 to define the outcome, as seen from the bettor.
     */
    function agentBet(bytes32 marketHash, address bettor, uint256 betAmount, uint256 odds, uint16 outcomeId)
        external
        whenNotPaused
    {
        if (_betAgents[bettor] != msg.sender) revert BetNotAllowed({owner: bettor, agent: msg.sender});
        _addBet(marketHash, bettor, betAmount, BetType.Market, odds, outcomeId);
    }

    /**
     * @notice Pays the bettor of a bet, if anything is won or returned, settles market first if necessary.
     * @notice Revert Error is emitted if not ready to settle/payout.
     * @param betHash is a hash identifying the bet.
     */
    function payoutBet(bytes32 betHash) external whenNotPaused {
        BetData storage sBet = bets[betHash];
        if (sBet.marketHash == 0) revert InvalidBet({betHash: betHash});
        if (betSettled[betHash]) return;
        betSettled[betHash] = true;

        MarketOutcomeData memory mod = _marketHandler.getOutcome(sBet.marketHash, sBet.outcomeId);
        // If market is not settled yet, do it now
        if (mod.result == MarketOutcomeResult.Undefined) {
            _marketHandler.settleMarket(sBet.marketHash);
            // Get the updated outcome data
            mod = _marketHandler.getOutcome(sBet.marketHash, sBet.outcomeId);
        }
        // Did settle just finish this outcome, or just no bettors left to pay?
        if (mod.betsSettled == mod.betsWagered) {
            // All winning bets are already settled for this outcome
            emit BetNoPayout(betHash, sBet.marketHash, sBet.bettor, sBet.outcomeId);
            return;
        }

        (uint256 bettorWin, uint256 bettorReturn) = _calcPayout(sBet.betAmount, sBet.odds, mod.result);
        uint256 payout = bettorWin + bettorReturn;

        BetSettleData memory bsd = BetSettleData({
            marketHash: sBet.marketHash,
            bettor: sBet.bettor,
            outcomeId: sBet.outcomeId,
            payout: payout,
            win: bettorWin
        });

        // Register the payout in the market and get the fees calculation, will unlock payout in the betbox
        (uint256 protoFees, uint256 bettorToMmFees) = _marketHandler.payoutBettor(bsd);

        // Unlock and pay the bettors return from this bet
        uint256 transferBettor = payout - bettorToMmFees - protoFees;
        ILockBox(_betBox).unlockAmountTo(sBet.marketHash, address(this), token, transferBettor);
        IERC20(token).transferFrom(_betBox, sBet.bettor, transferBettor);
        emit BettorPayout(
            betHash,
            sBet.marketHash,
            sBet.bettor,
            transferBettor,
            bettorWin,
            bettorReturn,
            bettorToMmFees,
            protoFees
        );
    }

    /**
     * @notice Pays the bettors of a list bets, settles market first if necessary.
     * @notice It accepts bets not elligible for payout but fails if all doesn't share same market.
     * @notice It is optimal to sort bets based on outcomes, to minimize lookups.
     * @notice Revert Error is emitted if payout fails.
     * @param betHashes is an array of hashes identifying the bets.
     */
    function payoutBets(bytes32[] calldata betHashes) external whenNotPaused {
        if (betHashes.length == 0) return;
        if (betHashes.length > MAX_PAYOUTS) revert LimitExceeded({limit: MAX_PAYOUTS});
        BetData storage sBet = bets[betHashes[0]];
        if (sBet.marketHash == 0) revert InvalidBet({betHash: betHashes[0]});
        bytes32 marketHash = sBet.marketHash;
        uint16 currentOutcomeId = sBet.outcomeId;

        // If market is not settled yet, do it now
        MarketOutcomeData memory mod = _marketHandler.getOutcome(marketHash, currentOutcomeId);
        if (mod.result == MarketOutcomeResult.Undefined) {
            _marketHandler.settleMarket(marketHash);
            // Get the updated outcome data
            mod = _marketHandler.getOutcome(marketHash, currentOutcomeId);
        }

        // Calc payouts and prepare settle data
        BetSettleData[] memory bsdList = new BetSettleData[](betHashes.length);
        for (uint i = 0; i < betHashes.length; i++) {
            bytes32 betHash = betHashes[i];
            sBet = bets[betHash];
            // Need to create a new instance to avoid reference changes to lower indexes
            BetSettleData memory bsd = BetSettleData({
                marketHash: marketHash,
                bettor: sBet.bettor,
                outcomeId: currentOutcomeId,
                payout: 0,
                win: 0
            });
            bsdList[i] = bsd;

            if (marketHash != sBet.marketHash) revert InvalidBet({betHash: betHash});
            if (currentOutcomeId != sBet.outcomeId) {
                currentOutcomeId = sBet.outcomeId;
                bsd.outcomeId = currentOutcomeId;
                mod = _marketHandler.getOutcome(marketHash, currentOutcomeId);
            }

            if (betSettled[betHash] || mod.betsSettled == mod.betsWagered) {
                betSettled[betHash] = true;
                emit BetNoPayout(betHash, marketHash, bsd.bettor, currentOutcomeId);
            } else {
                (uint256 bettorWin, uint256 bettorReturn) = _calcPayout(sBet.betAmount, sBet.odds, mod.result);
                bsd.win = bettorWin;
                bsd.payout = bettorWin + bettorReturn;
            }
        }

        // Process all bets and get the fees calculation, will unlock payout in the betbox
        (uint256[] memory protoFees, uint256[] memory b2mFees) = _marketHandler.payoutAll(bsdList);

        // Pay all the bettors
        for (uint i = 0; i < betHashes.length; i++) {
            bytes32 betHash = betHashes[i];
            BetSettleData memory bsd = bsdList[i];
            if (betSettled[betHash]) continue;
            betSettled[betHash] = true;
            // Unlock and pay the bettors return from this bet
            uint256 transferBettor = bsd.payout - b2mFees[i] - protoFees[i];
            ILockBox(_betBox).unlockAmountTo(marketHash, address(this), token, transferBettor);
            IERC20(token).transferFrom(_betBox, bsd.bettor, transferBettor);
            emit BettorPayout(
                betHash,
                bsd.marketHash,
                bsd.bettor,
                transferBettor,
                bsd.win,
                bsd.payout - bsd.win,
                b2mFees[i],
                protoFees[i]
            );
        }
    }

    /**
     * @notice Adds a bet to a market, based on a market hash and bet data.
     * @notice Error is emitted if the bet is not allowed, event if success.
     * @notice Restrictions in MarketHandler are made based on BETS_ROLE, so only the BetHandler can make the call.
     * @param marketHash is the hash that uniquely identifies the market.
     * @param bettor is the wallet address of the bettor (new bet owner).
     * @param betAmount is the amount of tokens the bettor is betting (backing) on the market.
     * @param betType is the type of the bet, e.g. regular market og agent.
     * @param odds is the odds accepted for this bet, in decimal-odds format.
     * @param outcomeId is a number from 0 - 65535 to define the outcome, as seen from the bettor.
     */
    function _addBet(
        bytes32 marketHash,
        address bettor,
        uint256 betAmount,
        BetType betType,
        uint256 odds,
        uint16 outcomeId
    ) private {
        if (betAmount == 0 || betType == BetType.Undefined) return;

        bettor.checkAllowanceAndBalance(betAmount, token, address(this));
        BetData memory bet = BetData({
            marketHash: marketHash,
            bettor: bettor,
            outcomeId: outcomeId,
            betType: betType,
            betAmount: betAmount,
            odds: odds
        });

        if (betAmount > MAX_BALANCE * 10**tokenDecimals)
            revert InvalidBetAmount(betAmount);

        MarketData memory sMarket = _marketHandler.getMarketData(marketHash);
        if (sMarket.marketType == kMarketType_Undefined) revert IMarketHandler.InvalidMarket(marketHash);
        MarketOutcomeData memory mod = _marketHandler.getOutcome(marketHash, outcomeId);
        if (odds != mod.odds) {
            revert InvalidOdds({
                marketHash: marketHash,
                outcomeId: outcomeId,
                requested: odds,
                expected: mod.odds
            });
        }

        // Add the bettors bet+tokens to the market, if liquidity and state is ok.
        _marketHandler.addBet(bet);

        IERC20(token).transferFrom(bettor, _betBox, betAmount);
        ILockBox(_betBox).lockAmount(marketHash, token, betAmount);

        bytes32 betHash = _getBetHash(bet);
        if (bets[betHash].betAmount != 0) revert InvalidBet({betHash: betHash});
        bets[betHash] = bet;
        emit BetAdded(betHash, marketHash, bettor, outcomeId, betType, betAmount, odds);
    }

    /**
     * @notice Initializes this contract with reference to other contracts.
     * @param inToken The Token used for betting.
     * @param inMarketHandler The MarketHandler contract address.
     * @param inBetBox The external box for tokens invested in bets.
     */
    function _init(address inToken, address inMarketHandler, address inBetBox) private {
        emit SetToken(inToken);
        token = inToken;
        tokenDecimals = IERC20Metadata(inToken).decimals();
        emit SetMarketHandler(inMarketHandler);
        _marketHandler = IMarketHandler(inMarketHandler);
        emit SetBetBox(inBetBox);
        _betBox = inBetBox;

        BaseInitializer.initialize();
    }

    /**
     * @notice Calculates the payout amounts (win and return) based on amount, odds and outcome.
     * @param betAmount is the amount betted.
     * @param odds is the odds of the bet, with extra precission digits.
     * @param result is the market outcome result (Win, HalfWin etc).
     * @return bettorWin is the bettors profit.
     * @return bettorReturn is the amount returned without causing fees (Void or betted amount for wins).
     */
    function _calcPayout(uint256 betAmount, uint256 odds, MarketOutcomeResult result)
        private
        pure
        returns (uint256 bettorWin, uint256 bettorReturn)
    {
        unchecked {
            // Calc bettor win and return (no fees on return amount)
            if (result == MarketOutcomeResult.Void) {
                // Everyone is refunded and no fees paid
                bettorReturn = betAmount;
            } else if (result == MarketOutcomeResult.HalfLoss) {
                // Bettors lost half, other half is Void
                bettorReturn = betAmount / 2;
            } else if (result == MarketOutcomeResult.Loss) {
                // Bettors lost all, no need for further calculations or updates
                return (0, 0);
            } else if (result == MarketOutcomeResult.HalfWin) {
                // Bettors won half, other half is Void
                bettorReturn = betAmount; // Void half and return half stake with no fees
                uint256 pot = bettorReturn * odds / ODDS_PRECISION;
                bettorWin = (pot - bettorReturn) / 2;
            } else if (result == MarketOutcomeResult.Win) {
                // Bettors won all
                bettorReturn = betAmount; // Return stake with no fee
                uint256 pot = bettorReturn * odds / ODDS_PRECISION;
                bettorWin = pot - bettorReturn;
            }
        }
    }


    /**
     * @notice Computes the hash of a bet. Based on select Bet data and the block number as salt.
     * @param bet The Bet to compute the hash for.
     * @return bytes32 The calculated hash of of the bet.
     */
    function _getBetHash(BetData memory bet) private view returns (bytes32) {
        return keccak256(abi.encode(bet.marketHash, bet.bettor, block.number));
    }
}
