// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./interfaces/IMarketmakerFactory.sol";
import "./interfaces/IMarketHandler.sol";
import "./interfaces/IMarketmakerBox.sol";
import "./interfaces/utils/ILockBox.sol";
import "./utils/TokenGating.sol";
import "./utils/ProcessorHandler.sol";
import "./utils/FeeHandler.sol";
import "./constants/markets.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Market Handling
 * @author betBase community
 * @notice Contract for handling markets, including storing data and firing chain events.
 * @notice This is a sub contract for the betBlox protocol.
 * @notice TokenGating is AccessHandler, AccessHandler is Initializable.
 */
contract MarketHandler is IMarketHandler, TokenGating, ProcessorHandler, FeeHandler {
    // market hash => market data
    mapping(bytes32 => MarketData) private markets;
    IEventHandler private _eventHandler;        // Address of the event handler that handles the event states/results.
    IMarketmakerFactory private _mmBoxFactory;  // Address of the factory that makes all the marketMakerBoxes.
    uint256 private _tokenMaxAmount;            // The maximum allowed token amount for liquidity, bets etc.
    address private _betBox;                    // Address of the bet box, where all tokens for markets are locked.
    uint256 private _marketCounter = 0;         // Used to create unique market hashes.

    /**
     * @dev Throws if called by any account other than the owner of a market.
     * @param marketHash is the hash of the market to check.
     */
    modifier onlyOwner(bytes32 marketHash) {
        if (markets[marketHash].owner != msg.sender)
            revert NotMarketOwner({marketHash: marketHash, add: msg.sender});
        _;
    }

    /**
     * @notice Default Constructor.
     */
    constructor() TokenGating() ProcessorHandler() FeeHandler() {}

    /**
     * @notice Initializes this contract with reference to other contracts and set gating options.
     * @param inEventHandler The EventHandler contract address.
     * @param inMMBF The MarketmakerBoxFactory contract address.
     * @param inFeeReceiver is the fee receiver address.
     * @param inFeePermilleBettor is the fee permille to charge for bettors.
     * @param inFeePermilleOracleMM is the fee permille to charge for marketmakers on Oracle events.
     * @param inFeePermilleOwnMM is the fee permille to charge for marketmakers on own events.
     * @param inMaxFeePermille is the max fee permille to charge from bettors to marketmakers.
     * @param inGatingToken The token to check balance for.
     * @param inGatingAmount0 Is preset amount 0 to use as balance requirement.
     * @param inGatingAmount1 Is preset amount 1 to use as balance requirement.
     * @param inGatingAmount2 Is preset amount 2 to use as balance requirement.
     */
    function initWithGating(
        address inEventHandler,
        address inMMBF,
        address inFeeReceiver,
        uint16 inFeePermilleBettor,
        uint16 inFeePermilleOracleMM,
        uint16 inFeePermilleOwnMM,
        uint16 inMaxFeePermille,
        address inGatingToken,
        uint256 inGatingAmount0,
        uint256 inGatingAmount1,
        uint256 inGatingAmount2
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setEventHandler(inEventHandler);
        _setMMBoxFactory(inMMBF);
        _initFees(inFeeReceiver, inFeePermilleBettor, inFeePermilleOracleMM, inFeePermilleOwnMM, inMaxFeePermille);
        _setGatingToken(inGatingToken);
        _setPresetGatingAmounts(inGatingAmount0, inGatingAmount1, inGatingAmount2);
        BaseInitializer.initialize();
    }

    /**
     * @notice Initializes this contract with reference to other contracts.
     * @param inEventHandler The EventHandler contract address.
     * @param inMMBF The MarketmakerBoxFactory contract address.
     * @param inFeeReceiver is the fee receiver address.
     * @param inFeePermilleBettor is the fee permille to charge for bettors.
     * @param inFeePermilleOracleMM is the fee permille to charge for marketmakers on Oracle events.
     * @param inFeePermilleOwnMM is the fee permille to charge for marketmakers on own events.
     * @param inMaxFeePermille is the max fee permille to charge from bettors to marketmakers.
     */
    function init(
        address inEventHandler,
        address inMMBF,
        address inFeeReceiver,
        uint16 inFeePermilleBettor,
        uint16 inFeePermilleOracleMM,
        uint16 inFeePermilleOwnMM,
        uint16 inMaxFeePermille
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setEventHandler(inEventHandler);
        _setMMBoxFactory(inMMBF);
        _initFees(inFeeReceiver, inFeePermilleBettor, inFeePermilleOracleMM, inFeePermilleOwnMM, inMaxFeePermille);
        BaseInitializer.initialize();
    }

    /**
     * @notice Adds a marketmaker market, based on an event hash and market data.
     * @notice Error is emitted if the market already exists or not allowed, event if success.
     * @notice Restrictions are made based on gating token balance.
     * @param inEventHash is the hash of the event to add a market for.
     * @param inAmount is the amount of bet tokens to add from the marketmaker.
     * @param inB2MmFeePermille is a market specific win fee rate, the bettors will pay to the marketmaker.
     * @param inMarketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
     * @param inGroup a number between 0 and 255, that limits the access to who can bet, 0 means no limitation.
     * @param inOffset is a number value used for some market types like "totals-goals", "spread" etc.
     * @param oddsList is a list of odds for the outcomes, in order matching the outcomeId constants.
     */
    function addMarket(
        bytes32 inEventHash,
        uint256 inAmount,
        uint16 inB2MmFeePermille,
        uint32 inMarketType,
        uint8 inGroup,
        int32 inOffset,
        uint256[] calldata oddsList
    )
        external
        hasMinBalance0
        whenNotPaused
    {
        bytes32 marketHash = keccak256(abi.encode("MarketHandler", msg.sender, ++_marketCounter));
        { // Scope set to avoid stack size errors
            // check inputs
            if (inAmount == 0) revert InvalidMarketLiquidityInput();
            if (inMarketType == kMarketType_Undefined) revert InvalidMarketTypeInput();
            if (!isValidOffset(inMarketType, inOffset))
                revert InvalidOffset({marketType: inMarketType, offset: inOffset});
            _validateFeeToMM(inB2MmFeePermille);
        }

        // Checks that event exists or creates it
        _eventHandler.checkOrAddEvent(inEventHash, inMarketType, msg.sender);

        { // Scope set to avoid stack size errors
            // Store the market data
            MarketData storage sMarket = markets[marketHash];
            sMarket.eventHash = inEventHash;
            sMarket.liquidity = inAmount;
            sMarket.b2MmFeePermille = inB2MmFeePermille;
            sMarket.marketType = inMarketType;
            sMarket.vipGroup = inGroup;
            sMarket.offset = inOffset;
            sMarket.owner = msg.sender;
            emit MarketAdded(marketHash, inEventHash, msg.sender, inMarketType, inB2MmFeePermille, inGroup, inOffset);
        }
        { // Scope set to avoid stack size errors
            IMarketmakerBox mmBox = IMarketmakerBox(_mmBoxFactory.marketmakerBoxes(msg.sender));
            if (address(mmBox) == ZERO_ADDRESS) revert NotMarketmaker(msg.sender);
            if (inAmount > _tokenMaxAmount) revert InvalidMarketLiquidityInput();
            // Add the MMs token to the market (liquidity)
            mmBox.reserveForMarket(inAmount);
            // Lock in the bet box
            ILockBox(_betBox).lockAmount(marketHash, _token, inAmount);
            emit MarketLiquidityAdded(marketHash, inAmount, inAmount);
        }
        // Private function to avoid stack size errors, adds outcome data
        _addMarketOutcomes(marketHash, oddsList);
    }

    /**
     * @notice Adds a bet to a market, based on a market hash and bet data.
     * @notice Error is emitted if the bet is not allowed, event if success.
     * @notice Restrictions are made based on BETS_ROLE, so only the BetHandler can make the call.
     * @param bet is a struct of data identifying the bet details.
     */
    function addBet(BetData calldata bet) external onlyRole(BETS_ROLE) {
        // We trust the bet data: amount, odds, outcome etc., as it comes from the BetHandler contract
        MarketData storage sMarket = markets[bet.marketHash];
        _eventHandler.assertEventIsActive(sMarket.eventHash);
        if (sMarket.vipGroup != 0) {
            IMarketmakerBox mmBox = IMarketmakerBox(_mmBoxFactory.marketmakerBoxes(sMarket.owner));
            bytes32 role = keccak256(abi.encode(sMarket.owner, sMarket.vipGroup));
            if (!mmBox.hasRole(role, bet.bettor)) revert NotVIP(bet.marketHash, bet.bettor, sMarket.vipGroup);
        }

        MarketOutcomeData storage mod = _getOutcome(bet.marketHash, bet.outcomeId);
        unchecked {
            uint256 matchAmount = bet.betAmount * mod.odds / ODDS_PRECISION - bet.betAmount;
            if (mod.available < matchAmount) {
                revert InsufficientLiquidity({
                    marketHash: bet.marketHash,
                    outcomeId: mod.outcomeId,
                    available: mod.available,
                    required: matchAmount
                });
            }
            mod.available -= matchAmount;
            mod.betsWagered++;
            mod.betAmount += bet.betAmount;
            mod.b2MmFee += sMarket.b2MmFeePermille * matchAmount / 1000;
            sMarket.betVolume += bet.betAmount;
        }
    }

    /**
     * @notice Adds additional liquidity for a market.
     * @notice Revert Error is emitted if event is not active.
     * @param marketHash is the hash of the market to update.
     * @param inAmount is the amount of bet tokens to add from the marketmaker.
     */
    function addLiquidity(bytes32 marketHash, uint256 inAmount)
        external
        onlyOwner(marketHash)
        hasMinBalance0
        whenNotPaused
    {
        MarketData storage sMarket = markets[marketHash];
        address owner = msg.sender;
        _eventHandler.assertEventIsActive(sMarket.eventHash);

        // Add the MMs token to the market
        IMarketmakerBox mmBox = IMarketmakerBox(_mmBoxFactory.marketmakerBoxes(owner));
        mmBox.reserveForMarket(inAmount);
        ILockBox(_betBox).lockAmount(marketHash, _token, inAmount);
        uint256 newBalance = inAmount + sMarket.liquidity;
        unchecked {
            if (newBalance > _tokenMaxAmount) revert InvalidMarketLiquidityInput();
            sMarket.liquidity = newBalance;
            // Add the tokens available for each outcome
            for (uint i = 0; i < sMarket.outcomes.length; i++) {
                sMarket.outcomes[i].available += inAmount;
            }
        }
        emit MarketLiquidityAdded(marketHash, inAmount, sMarket.liquidity);
    }

    /**
     * @notice Removes unused liquidity for a market.
     * @notice Revert Error is emitted if event is not active/playing or liquidity is not available.
     * @param marketHash is the hash of the market to update.
     * @param inAmount is the amount of bet tokens to return to the marketmaker.
     */
    function removeLiquidity(bytes32 marketHash, uint256 inAmount)
        external
        onlyOwner(marketHash)
        hasMinBalance0
        whenNotPaused
    {
        MarketData storage sMarket = markets[marketHash];
        address owner = msg.sender;
        _eventHandler.assertEventIsActiveOrPlaying(sMarket.eventHash);

        unchecked {
            // Decrease the tokens available for each outcome
            for (uint i = 0; i < sMarket.outcomes.length; i++) {
                if (sMarket.outcomes[i].available < inAmount) {
                    revert InsufficientLiquidity({
                        marketHash: marketHash,
                        outcomeId: sMarket.outcomes[i].outcomeId,
                        available: sMarket.outcomes[i].available,
                        required: inAmount
                    });
                }
                sMarket.outcomes[i].available -= inAmount;
            }
            // Decrease liquidity
            sMarket.liquidity -= inAmount;
        }
        // Unlock liquidity
        IMarketmakerBox mmBox = IMarketmakerBox(_mmBoxFactory.marketmakerBoxes(owner));
        ILockBox(_betBox).unlockAmountTo(marketHash, address(mmBox), _token, inAmount);
        // Pay the MM and register in his mmBox
        mmBox.returnToOwner(inAmount);

        emit MarketLiquidityRemoved(marketHash, inAmount, sMarket.liquidity);
    }

    /**
     * @notice Changes the odds for a market on a specific outcome.
     * @notice Revert Error is emitted if event is not active or inputs are invalid.
     * @param marketHash is the hash of the market to update.
     * @param outcomeId is the outcome id of the outcome to update.
     * @param inOdds is the new odds value for the outcome.
     */
    function setOdds(bytes32 marketHash, uint16 outcomeId, uint256 inOdds) external onlyOwner(marketHash) {
        MarketData storage sMarket = markets[marketHash];
        _eventHandler.assertEventIsActive(sMarket.eventHash);
        if (inOdds <= ODDS_PRECISION || inOdds > ODDS_PRECISION * MAX_ODDS) {
            revert InvalidMarketOddsInput();
        }

        // Set the new odds value for the outcome
        for (uint i = 0; i < sMarket.outcomes.length; i++) {
            if (sMarket.outcomes[i].outcomeId == outcomeId) {
                sMarket.outcomes[i].odds = inOdds;
                emit MarketOutcomeUpdated(marketHash, inOdds, outcomeId);
                return;
            }
        }
        revert InvalidMarketOddsInput();
    }

    /**
     * @notice Settles a market to prepare it for payouts.
     * @notice Revert Error is emitted if not ready to settle.
     * @param marketHash is the hash of the market to settle.
     */
    function settleMarket(bytes32 marketHash) external whenNotPaused {
        _settleMarket(marketHash);
    }

    /**
     * @notice Pays the marketmaker of a single market and all bettors, settles first if necessary.
     * @notice This can only be called from the BetHandler as trusted bet settle data is needed as input.
     * @notice It skips bets not elligible for a payout and assumes all share same market.
     * @notice It is optimal to sort bets based on outcomes, to minimize lookups.
     * @notice Revert Error is emitted if payout fails.
     * @param bets is an array of structs of data identifying the bets details.
     */
    function payoutAll(BetSettleData[] calldata bets)
        external
        onlyRole(BETS_ROLE)
        returns (uint256[] memory protoFees, uint256[] memory b2mFees)
    {
        // At least 1 bet should be provided
        if (bets.length == 0) return (protoFees, b2mFees);

        bytes32 marketHash = bets[0].marketHash;
        MarketData storage sMarket = markets[marketHash];
        if (sMarket.marketType == kMarketType_Undefined) revert InvalidMarket({marketHash: marketHash});
        if (!sMarket.settled) _settleMarket(marketHash);

        // Payout marketmaker if necessary
        if (!sMarket.mmPaid) _payoutMarketmaker(marketHash);

        protoFees = new uint256[](bets.length);
        b2mFees = new uint256[](bets.length);

        // Pay all bets
        bool checkAllPaid = false;
        uint16 currentOutcomeId = bets[0].outcomeId;
        MarketOutcomeData storage mod = _getOutcome(marketHash, currentOutcomeId);
        for (uint i = 0; i < bets.length; i++) {
            BetSettleData calldata bet = bets[i];
            if (bet.payout == 0) continue;
            checkAllPaid = true;
            if (currentOutcomeId != bet.outcomeId) {
                currentOutcomeId = bet.outcomeId;
                mod = _getOutcome(marketHash, bet.outcomeId);
            }

            // Increase settle count before internal payout
            mod.betsSettled++;
            (protoFees[i], b2mFees[i]) = _payoutBettor(bet);
        }

        // Check if all bets are paid for all outcomes?
        if (checkAllPaid) _checkAllPaid(marketHash);
    }

    /**
     * @notice Pays the marketmaker of a market, settles first if necessary.
     * @notice Revert Error is emitted if not ready to settle/payout.
     * @param marketHash is the hash of the market to payout.
     */
    function payoutMarketmaker(bytes32 marketHash) external whenNotPaused {
        MarketData storage sMarket = markets[marketHash];
        if (sMarket.marketType == kMarketType_Undefined) revert InvalidMarket({marketHash: marketHash});
        if (sMarket.mmPaid) revert InvalidMarketState({marketHash: marketHash});
        if (!sMarket.settled) _settleMarket(marketHash);
        _payoutMarketmaker(marketHash);
    }

    /**
     * @notice Pays the bettor of a market, settles first if necessary.
     * @notice Revert Error is emitted if not ready to settle/payout.
     *         The data can be trusted,, as the function call is protected by a BET_ROLE (BetHandler only).
     * @param bet is a struct of data identifying the bet details.
     * @return protoFees is the amount of fees paid by the bettor to the protocol.
     * @return b2mFees is the amount of fees paid by the bettor to the marketmaker.
     */
    function payoutBettor(BetSettleData calldata bet)
        external
        onlyRole(BETS_ROLE)
        returns (uint256 protoFees, uint256 b2mFees)
    {
        // We trust the bet data: amount, odds, outcome etc., as it comes from the BetHandler contract
        MarketData storage sMarket = markets[bet.marketHash];
        if (sMarket.marketType == kMarketType_Undefined) revert InvalidMarket({marketHash: bet.marketHash});
        MarketOutcomeData storage mod = _getOutcome(bet.marketHash, bet.outcomeId);

        // Increase and check settle count
        bool marketBettorsPaid = ++mod.betsSettled == mod.betsWagered;
        // Pay the bettor
        (protoFees, b2mFees) = _payoutBettor(bet);
        // Are all bettors and marketmaker settled/paid now?
        if (marketBettorsPaid) _checkAllPaid(bet.marketHash);
    }

    /**
     * @notice Changes the VIP group (0-255) for a market. VIP roles for values 1-254 can be assigned.
     * @notice VIP group 0 is meant for unlimited access and 255 is for no access (betting disabled).
     * @notice Revert Error is emitted if event is not active or inputs are invalid.
     * @param marketHash is the hash of the market to update.
     * @param inGroup is the new VIP group value for the market.
     */
    function setVIPGroup(bytes32 marketHash, uint8 inGroup) external onlyOwner(marketHash) {
        MarketData storage sMarket = markets[marketHash];
        _eventHandler.assertEventIsActive(sMarket.eventHash);
        emit VIPGroupUpdated(marketHash, inGroup, sMarket.vipGroup);
        sMarket.vipGroup = inGroup;
    }

    /**
     * @notice Get all data of a market.
     * @param marketHash is the hash of the market to find.
     * @return MarketData is the data, 0-data if the market does not exist.
     */
    function getMarketData(bytes32 marketHash) external view returns (MarketData memory) {
        return markets[marketHash];
    }

    /**
     * @notice Get the event state of a market.
     * @param marketHash is the hash of the market to investigate.
     * @return EventState is the event state of the supplied market.
     */
    function getEventState(bytes32 marketHash) external view returns (EventState) {
        return _eventHandler.getEventState(markets[marketHash].eventHash);
    }

    /**
     * @dev Returns the address of the current owner of a market.
     * @param marketHash is the hash of the market to look up.
     * @return The wallet address of the marketmaker.
     */
    function getOwner(bytes32 marketHash) external view returns (address) {
        return markets[marketHash].owner;
    }

    /**
     * @notice Check if an outcome exists for a specific market.
     * @param marketHash is the hash of the event to check.
     * @param outcomeId is the unique id of an outcome to check.
     * @return True if the outcome exist, false if not.
     */
    function hasOutcome(bytes32 marketHash, uint16 outcomeId) external view returns (bool) {
        // Checks that the market exists
        MarketData storage sMarket = markets[marketHash];
        if (sMarket.marketType == kMarketType_Undefined) return false;

        for (uint i = 0; i < sMarket.outcomes.length; i++) {
            if (sMarket.outcomes[i].outcomeId == outcomeId) return true;
        }
        return false;
    }

    /**
     * @notice Finds an outcome for a specific market.
     * @param marketHash is the hash of the event to check.
     * @param outcomeId is the unique id of an outcome to check.
     * @return the matching outcome data, if the outcome exist, reverts if not.
     */
    function getOutcome(bytes32 marketHash, uint16 outcomeId) external view returns (MarketOutcomeData memory) {
        return _getOutcome(marketHash, outcomeId);
    }

    /**
     * @notice Returns the processor contract address for an id.
     * @param id is the id (market type) of the item to process.
     * @return address of related processor, 0 address if not defined.
     */
    function getProcessor(uint32 id) external view virtual override returns (address) {
        if (_isProcessor(id)) return address(this);
        return _processors[id];
    }

    /**
     * @notice Implements IMarketProcessor.
     * @notice Check if an outcomeId is valid for a specific marketType.
     * @param inMarketType is the type of the market to check.
     * @param inOutcomeId is the unique id of an outcome to check.
     * @return True if the outcome id is valid for the market type, false if not.
     */
    function isValidOutcome(uint32 inMarketType, uint16 inOutcomeId) external view returns (bool) {
        address proc = _processors[inMarketType];
        if (proc != ZERO_ADDRESS) {
            // An external processor is registered
            return IMarketProcessor(proc).isValidOutcome(inMarketType, inOutcomeId);
        }
        if (_isProcessor(inMarketType)) {
            // Process here instead
            if (inMarketType >= kMarketType_MoneyLine && inMarketType <= kMarketType_MoneyLine_Away) {
                // Moneyline markets
                if (inMarketType == kMarketType_MoneyLine_Home) return inOutcomeId == kOutcome_HomeWin;
                if (inMarketType == kMarketType_MoneyLine_Away) return inOutcomeId == kOutcome_AwayWin;
                return (inOutcomeId == kOutcome_HomeWin || inOutcomeId == kOutcome_AwayWin);
            } else if (inMarketType >= kMarketType_FulltimeResult && inMarketType <= kMarketType_FulltimeResult_2) {
                // Fulltime result markets
                if (inMarketType == kMarketType_FulltimeResult_1) return inOutcomeId == kOutcome_HomeWin;
                if (inMarketType == kMarketType_FulltimeResult_X) return inOutcomeId == kOutcome_Draw;
                if (inMarketType == kMarketType_FulltimeResult_2) return inOutcomeId == kOutcome_AwayWin;
                return (
                    inOutcomeId == kOutcome_HomeWin ||
                    inOutcomeId == kOutcome_Draw ||
                    inOutcomeId == kOutcome_AwayWin
                );
            } else if (inMarketType >= kMarketType_Spread && inMarketType <= kMarketType_Spread_2) {
                // Spread markets - with acceptable offsets of quarters, and outcomes like Moneyline.
                if (inMarketType == kMarketType_Spread_1) return inOutcomeId == kOutcome_HomeWin;
                if (inMarketType == kMarketType_Spread_2) return inOutcomeId == kOutcome_AwayWin;
                return (inOutcomeId == kOutcome_HomeWin || inOutcomeId == kOutcome_AwayWin);
            } else if (inMarketType >= kMarketType_Total && inMarketType <= kMarketType_Total_Under) {
                // Total markets - with acceptable offsets of halves, and outcomes O/U, settling incl. push/void.
                if (inMarketType == kMarketType_Total_Over) return inOutcomeId == kOutcome_Over;
                if (inMarketType == kMarketType_Total_Under) return inOutcomeId == kOutcome_Under;
                return (inOutcomeId == kOutcome_Over || inOutcomeId == kOutcome_Under);
            } else if (inMarketType >= kMarketType_Prediction1 && inMarketType <= kMarketType_Prediction5) {
                // Prediction markets 1 - 5 outcomes, with ids matching the market type values
                return (inOutcomeId >= kOutcome_Prediction1 && inOutcomeId <= inMarketType);
            }
            return false;
        } else {
            revert InvalidMarketType(inMarketType);
        }
    }

    /**
     * @notice Implements IMarketProcessor.
     * @notice Find the winning outcomeId for a market, based on the event result.
     * @notice It is assumed that the event is completed (not canceled/invalid) and the inResult is valid.
     * @param inMarketType is the type of the market to check.
     * @param inOffset is a number value used for some market types like "totals-goals", "spread" etc.
     * @param inResult is the result of the corresponding event.
     * @return outcomeId is the unique id of the winning outcome.
     * @return result is type of result, halfWin, loss, void etc.
     */
    function getWinningOutcome(uint32 inMarketType, int32 inOffset, EventResult memory inResult)
        public
        view
        returns (uint16 outcomeId, MarketOutcomeResult result)
    {
        address proc = _processors[inMarketType];
        if (proc != ZERO_ADDRESS) {
            // An external processor is registered
            return IMarketProcessor(proc).getWinningOutcome(inMarketType, inOffset, inResult);
        }
        outcomeId = kOutcome_Undefined;
        result = MarketOutcomeResult.Undefined;
        if (_isProcessor(inMarketType)) {
            unchecked {
                // Process here instead
                if (inMarketType >= kMarketType_MoneyLine && inMarketType <= kMarketType_MoneyLine_Away) {
                    if (inResult.homeScore == inResult.awayScore) {
                        outcomeId = kOutcome_Undefined;
                        result = MarketOutcomeResult.Void;
                    } else if (inResult.homeScore > inResult.awayScore) {
                        outcomeId = kOutcome_HomeWin;
                        result = MarketOutcomeResult.Win;
                    } else if (inResult.homeScore < inResult.awayScore) {
                        outcomeId = kOutcome_AwayWin;
                        result = MarketOutcomeResult.Win;
                    }
                } else if (inMarketType >= kMarketType_FulltimeResult && inMarketType <= kMarketType_FulltimeResult_2) {
                    if (inResult.homeScore == inResult.awayScore) {
                        outcomeId = kOutcome_Draw;
                    } else if (inResult.homeScore > inResult.awayScore) {
                        outcomeId = kOutcome_HomeWin;
                    } else if (inResult.homeScore < inResult.awayScore) {
                        outcomeId = kOutcome_AwayWin;
                    }
                    result = MarketOutcomeResult.Win;
                } else if (inMarketType >= kMarketType_Spread && inMarketType <= kMarketType_Spread_2) {
                    // Offset is the spread with 2 precission digits, to support quarter offsets
                    bool integer = inOffset % 100 == 0;
                    bool half = inOffset % 100 == 50 || inOffset % 100 == -50;
                    // Add the offset to precission adjusted scores to be able to compare relatively
                    int32 precissionHomeScore = int32(uint32(inResult.homeScore)) * 100 + inOffset;
                    int32 precissionAwayScore = int32(uint32(inResult.awayScore)) * 100;
                    if (integer || half) {
                        //  Treat like a Moneyline bet, with only Win, Loss and Void possible.
                        if (precissionHomeScore == precissionAwayScore) {
                            // Is only possible for integer offsets
                            outcomeId = kOutcome_Undefined;
                            result = MarketOutcomeResult.Void;
                        } else if (precissionHomeScore > precissionAwayScore) {
                            outcomeId = kOutcome_HomeWin;
                            result = MarketOutcomeResult.Win;
                        } else if (precissionHomeScore < precissionAwayScore) {
                            outcomeId = kOutcome_AwayWin;
                            result = MarketOutcomeResult.Win;
                        }
                    } else {
                        // The case is +/- quarter or three-quarter offset, and could result in HalfWin/HalfLoss.
                        // Full Void is not possible.
                        if (precissionHomeScore > precissionAwayScore) {
                            // Win or HalfWin for the HomeWin bets
                            if (precissionHomeScore - 25 > precissionAwayScore)
                                result = MarketOutcomeResult.Win;
                            else
                                result = MarketOutcomeResult.HalfWin;
                            outcomeId = kOutcome_HomeWin;
                        } else if (precissionHomeScore < precissionAwayScore) {
                            // Win or HalfWin for the AwayWin bets
                            if (precissionHomeScore + 25 < precissionAwayScore)
                                result = MarketOutcomeResult.Win;
                            else
                                result = MarketOutcomeResult.HalfWin;
                            outcomeId = kOutcome_AwayWin;
                        }
                    }
                } else if (inMarketType >= kMarketType_Total && inMarketType <= kMarketType_Total_Under) {
                    // Offset is the Total with 2 precission digits, to support quarter offsets
                    bool integer = inOffset % 100 == 0;
                    bool half = inOffset % 100 == 50 || inOffset % 100 == -50;
                    // Get precission adjusted scores to be able to compare relatively to offset (result Total).
                    int32 precissionTotalScore = int32(uint32(inResult.homeScore + inResult.awayScore)) * 100;
                    if (integer || half) {
                        //  Treat like a Moneyline bet, with only Win, Loss and Void possible.
                        if (precissionTotalScore == inOffset) {
                            // Is only possible for integer offsets
                            outcomeId = kOutcome_Undefined;
                            result = MarketOutcomeResult.Void;
                        } else if (precissionTotalScore > inOffset) {
                            outcomeId = kOutcome_Over;
                            result = MarketOutcomeResult.Win;
                        } else if (precissionTotalScore < inOffset) {
                            outcomeId = kOutcome_Under;
                            result = MarketOutcomeResult.Win;
                        }
                    } else {
                        // The case is quarter or three-quarter offset, and could result in HalfWin/HalfLoss.
                        // Full Void is not possible.
                        if (precissionTotalScore > inOffset) {
                            // Win or HalfWin for the HomeWin bets
                            if (precissionTotalScore - 25 > inOffset)
                                result = MarketOutcomeResult.Win;
                            else
                                result = MarketOutcomeResult.HalfWin;
                            outcomeId = kOutcome_Over;
                        } else if (precissionTotalScore < inOffset) {
                            // Win or HalfWin for the AwayWin bets
                            if (precissionTotalScore + 25 < inOffset)
                                result = MarketOutcomeResult.Win;
                            else
                                result = MarketOutcomeResult.HalfWin;
                            outcomeId = kOutcome_Under;
                        }
                    }
                } else if (inMarketType >= kMarketType_Prediction1 && inMarketType <= kMarketType_Prediction5) {
                    // We made sure the outcomeId values are continuous from kOutcome_Prediction1 and up.
                    outcomeId = inResult.prediction - 1 + kOutcome_Prediction1;
                    result = MarketOutcomeResult.Win;
                }
            }
        } else {
            revert InvalidMarketType(inMarketType);
        }
    }

    /**
     * @notice Implements IMarketProcessor.
     * @notice Check an offset value (with 2 precission decimals) against a specific market type.
     * @param inMarketType is the type of the market to check.
     * @param inOffset is a number value used for some market types like "totals-goals", "spread" etc.
     */
    function isValidOffset(uint32 inMarketType, int32 inOffset) public view returns (bool) {
        address proc = _processors[inMarketType];
        if (proc != ZERO_ADDRESS) {
            // An external processor is registered
            return IMarketProcessor(proc).isValidOffset(inMarketType, inOffset);
        }
        if (_isProcessor(inMarketType)) {
            // Process here instead
            if (inMarketType >= kMarketType_Spread && inMarketType <= kMarketType_Spread_2) {
                // Spread markets - with acceptable offsets of +/- quarters, and outcomes like Moneyline.
                if (inOffset % 25 != 0) return false;
                // Valid handicap values of -1000 - 1000
                if (inOffset > MAX_SPREAD || inOffset < -MAX_SPREAD) return false;
                return true;
            } else if (inMarketType >= kMarketType_Total && inMarketType <= kMarketType_Total_Under) {
                // Total markets - with positive offsets of quarters, and outcomes O/U, settling incl. push/void.
                // Offset is the Total with 2 precission digits, so matches format of Spread offsets.
                if (inOffset % 25 != 0) return false;
                // Valid Total values of 0 - 10,000
                if (inOffset > MAX_TOTAL || inOffset <= 0) return false;
                return true;
            }
            // No offset is expected, so make sure it 0
            return inOffset == 0;
        } else {
            revert InvalidMarketType(inMarketType);
        }
    }

    /**
     * @notice Implements IMarketProcessor.
     * @notice Get all valid outcomeId for a specific marketType.
     * @param inMarketType is the type of the market to match.
     * @return outcomes is the list of matching outcomeId.
     */
    function getValidOutcomes(uint32 inMarketType) public view returns (uint16[] memory outcomes) {
        address proc = _processors[inMarketType];
        if (proc != ZERO_ADDRESS) {
            // An external processor is registered
            return IMarketProcessor(proc).getValidOutcomes(inMarketType);
        }
        if (_isProcessor(inMarketType)) {
            // Process here instead
            outcomes = new uint16[](1);
            if (inMarketType >= kMarketType_MoneyLine && inMarketType <= kMarketType_MoneyLine_Away) {
                // Moneyline markets
                if (inMarketType == kMarketType_MoneyLine_Home) outcomes[0] = kOutcome_HomeWin;
                else if (inMarketType == kMarketType_MoneyLine_Away) outcomes[0] = kOutcome_AwayWin;
                else {
                    outcomes = new uint16[](2);
                    outcomes[0] = kOutcome_HomeWin;
                    outcomes[1] = kOutcome_AwayWin;
                }
            }
            else if (inMarketType >= kMarketType_FulltimeResult && inMarketType <= kMarketType_FulltimeResult_2) {
                // Fulltime result markets
                if (inMarketType == kMarketType_FulltimeResult_1) outcomes[0] = kOutcome_HomeWin;
                else if (inMarketType == kMarketType_FulltimeResult_2) outcomes[0] = kOutcome_AwayWin;
                else if (inMarketType == kMarketType_FulltimeResult_X) outcomes[0] = kOutcome_Draw;
                else {
                    outcomes = new uint16[](3);
                    outcomes[0] = kOutcome_HomeWin;
                    outcomes[1] = kOutcome_AwayWin;
                    outcomes[2] = kOutcome_Draw;
                }
            } else if (inMarketType >= kMarketType_Spread && inMarketType <= kMarketType_Spread_2) {
                // Spread markets - with acceptable offsets of quarters, and outcomes like Moneyline.
                if (inMarketType == kMarketType_Spread_1) outcomes[0] = kOutcome_HomeWin;
                else if (inMarketType == kMarketType_Spread_2) outcomes[0] = kOutcome_AwayWin;
                else {
                    outcomes = new uint16[](2);
                    outcomes[0] = kOutcome_HomeWin;
                    outcomes[1] = kOutcome_AwayWin;
                }
            } else if (inMarketType >= kMarketType_Total && inMarketType <= kMarketType_Total_Under) {
                // Total markets - with acceptable offsets of halves, and outcomes O/U, settling incl. push/void.
                if (inMarketType == kMarketType_Total_Over) outcomes[0] = kOutcome_Over;
                else if (inMarketType == kMarketType_Total_Under) outcomes[0] = kOutcome_Under;
                else {
                    outcomes = new uint16[](2);
                    outcomes[0] = kOutcome_Over;
                    outcomes[1] = kOutcome_Under;
                }
            } else if (inMarketType >= kMarketType_Prediction1 && inMarketType <= kMarketType_Prediction5) {
                // Prediction markets 1 - 5 outcomes, with ids matching the market type values
                if (inMarketType == kMarketType_Prediction1) outcomes[0] = kOutcome_Prediction1;
                else if (inMarketType == kMarketType_Prediction2) {
                    outcomes = new uint16[](2);
                    outcomes[0] = kOutcome_Prediction1;
                    outcomes[1] = kOutcome_Prediction2;
                } else if (inMarketType == kMarketType_Prediction3){
                    outcomes = new uint16[](3);
                    outcomes[0] = kOutcome_Prediction1;
                    outcomes[1] = kOutcome_Prediction2;
                    outcomes[2] = kOutcome_Prediction3;
                } else if (inMarketType == kMarketType_Prediction4) {
                    outcomes = new uint16[](4);
                    outcomes[0] = kOutcome_Prediction1;
                    outcomes[1] = kOutcome_Prediction2;
                    outcomes[2] = kOutcome_Prediction3;
                    outcomes[3] = kOutcome_Prediction4;
                } else {
                    outcomes = new uint16[](5);
                    outcomes[0] = kOutcome_Prediction1;
                    outcomes[1] = kOutcome_Prediction2;
                    outcomes[2] = kOutcome_Prediction3;
                    outcomes[3] = kOutcome_Prediction4;
                    outcomes[4] = kOutcome_Prediction5;
                }
            }
        } else {
            revert InvalidMarketType(inMarketType);
        }
    }

    /**
     * @notice Add all market outcomes for a new market.
     * @notice Revert Error is emitted if invalid inputs.
     * @param marketHash is the hash of the market to update.
     * @param oddsList is a list of odds for the outcomes, in order matching the outcomeId constants.
     */
    function _addMarketOutcomes(bytes32 marketHash, uint256[] calldata oddsList) private {
        MarketData storage sMarket = markets[marketHash];
        uint16[] memory outcomesList = getValidOutcomes(sMarket.marketType);
        if (oddsList.length != outcomesList.length) revert InvalidMarketOutcomesInput();

        for (uint i = 0; i < oddsList.length; i++) {
            MarketOutcomeData storage newOutcome = sMarket.outcomes.push();
            newOutcome.available = sMarket.liquidity;
            newOutcome.odds = oddsList[i];
            newOutcome.outcomeId = outcomesList[i];
            if (newOutcome.odds <= ODDS_PRECISION || newOutcome.odds > ODDS_PRECISION * MAX_ODDS)
                revert InvalidMarketOddsInput();
            emit MarketOutcomeUpdated(marketHash, newOutcome.odds, newOutcome.outcomeId);
        }
    }

    /**
     * @notice Settles a market to prepare it for payouts.
     * @notice Revert Error is emitted if not ready to settle og outcome is undefined.
     * @param marketHash is the hash of the market to settle.
     */
    function _settleMarket(bytes32 marketHash) private {
        // Checks that the market exists
        MarketData storage sMarket = markets[marketHash];
        if (sMarket.marketType == kMarketType_Undefined) revert InvalidMarket({marketHash: marketHash});
        if (sMarket.settled) revert InvalidMarketState({marketHash: marketHash});
        // Checks that the event is Completed, Canceled or Invalid, and get winning outcome
        (uint16 winOutcomeId, MarketOutcomeResult result) = _getWinningOutcome(sMarket);
        if (result == MarketOutcomeResult.Undefined) revert InvalidMarketType({ marketType: sMarket.marketType });

        // Set the outcome "result" for all available outcomes
        bool bettorsPaid = true;
        if (result == MarketOutcomeResult.Void) {
            for (uint i = 0; i < sMarket.outcomes.length; i++) {
                sMarket.outcomes[i].result = result;
                if (sMarket.outcomes[i].betsSettled < sMarket.outcomes[i].betsWagered)
                    bettorsPaid = false;
            }
        } else {
            for (uint i = 0; i < sMarket.outcomes.length; i++) {
                MarketOutcomeData storage mod = sMarket.outcomes[i];
                if (mod.outcomeId == winOutcomeId) {
                    mod.result = result;
                    if (mod.betsSettled < mod.betsWagered)
                        bettorsPaid = false;
                } else {
                    // Adjust the losing result type, Loss/HalfLoss
                    if (result == MarketOutcomeResult.HalfWin) {
                        mod.result = MarketOutcomeResult.HalfLoss;
                        if (mod.betsSettled < mod.betsWagered)
                            bettorsPaid = false;
                    }
                    else {
                        mod.result = MarketOutcomeResult.Loss;
                        mod.betsSettled = mod.betsWagered;
                    }
                }
            }
        }
        if (bettorsPaid) sMarket.bettorsPaid = true;
        sMarket.settled = true;
        emit MarketSettled(marketHash, winOutcomeId, result, sMarket.liquidity + sMarket.betVolume);
    }

    /**
     * @notice Tries to make a payout. Throws if attempt fails
     * @param marketHash is the hash of the market to handle.
     * @param payout is the size of the requested payout.
     */
    function _attemptPayout(bytes32 marketHash, uint256 payout) private {
        if (payout == 0) return;
        MarketData storage sMarket = markets[marketHash];
        unchecked {
            uint256 remainingAmount = sMarket.liquidity + sMarket.betVolume - sMarket.paid;
            if (payout > remainingAmount) {
                revert InvalidMarketPayout({marketHash: marketHash, requested: payout, remaining: remainingAmount});
            }
            sMarket.paid += payout;
        }
    }

    /**
     * @notice Checks if all participants are paid, and transfers any diff to the fee receiver.
     * @notice Emits event if market is fully paid.
     * @param marketHash is the hash of the market to handle.
     */
    function _checkAllPaid(bytes32 marketHash) private {
        MarketData storage sMarket = markets[marketHash];
        if (!sMarket.bettorsPaid) {
            sMarket.bettorsPaid = true;
            for (uint i = 0; i < sMarket.outcomes.length; i++) {
                MarketOutcomeData storage modCheck = sMarket.outcomes[i];
                if (modCheck.betsSettled < modCheck.betsWagered) {
                    sMarket.bettorsPaid = false;
                    break;
                }
            }
        }
        // Are all bettors and marketmaker settled/paid now?
        if (sMarket.mmPaid && sMarket.bettorsPaid) {
            unchecked {
                // diff is the amount not paid from the total pool size, due to rounding. Transfer it to the fee receiver.
                uint256 diff = sMarket.liquidity + sMarket.betVolume - sMarket.paid;
                if (diff > 0) {
                    ILockBox(_betBox).unlockAmountTo(marketHash, address(this), _token, diff);
                    IERC20(_token).transferFrom(_betBox, feeReceiver, diff);
                }
                emit MarketPaid(marketHash, sMarket.liquidity + sMarket.betVolume, sMarket.paid, diff);
            }
        }
    }

    /**
     * @notice Setter to change the referenced BetBox (LockBox) contract.
     * @param inBetBox The BetBox contract address.
     */
    function _setBetBox(address inBetBox) private {
        emit SetBetBox(inBetBox);
        _betBox = inBetBox;
    }

    /**
     * @notice Setter to change the referenced EventHandler contract.
     * @param inEventHandler The EventHandler contract address.
     */
    function _setEventHandler(address inEventHandler) private {
        emit SetEventHandler(inEventHandler);
        _eventHandler = IEventHandler(inEventHandler);
    }

    /**
     * @notice Setter to change the referenced MarketMakerBoxFactory contract.
     * @notice Sets the token and betBox as they are set in the factory.
     * @param inFactory The MarketmakerBoxFactory contract address.
     */
    function _setMMBoxFactory(address inFactory) private {
        emit SetMarketmakerBoxFactory(inFactory);
        _mmBoxFactory = IMarketmakerFactory(inFactory);
        _setBetBox(_mmBoxFactory.betBox());
        _setToken(_mmBoxFactory.token());
        // Set token max based on the token precission digits and the MAX constant
        _tokenMaxAmount = MAX_BALANCE * 10**IERC20Metadata(_token).decimals();
    }

    /**
     * @notice Pays the marketmaker of a market, assumes settle is done.
     * @notice Revert Error is emitted if payout fails.
     * @param marketHash is the hash of the market to payout.
     */
    function _payoutMarketmaker(bytes32 marketHash) private {
        MarketData storage sMarket = markets[marketHash];

        // MM should get paid any unmatched amount (not won by bettors) on the winning outcome.
        // Additinally MM should be returned any incoming bettor amounts on losing outcomes.
        uint256 mmWin;
        uint256 mmReturn;
        uint256 bettorToMmFees;
        uint256 payout;
        uint256 protoFees;
        uint256 transferMM;
        unchecked {
            bool halfVoid;
            bool returnedAvailable;
            for (uint i = 0; i < sMarket.outcomes.length; i++) {
                MarketOutcomeData storage mod = sMarket.outcomes[i];
                if (mod.result == MarketOutcomeResult.Void) {
                    // Everyone is refunded and no fees paid
                    break;
                }
                if (mod.result == MarketOutcomeResult.HalfLoss) {
                    // Bettors lost half, other half is Void
                    // MM gets half the bets as win, and should get half void once per market
                    halfVoid = true;
                    mmWin += mod.betAmount / 2;
                } else if (mod.result == MarketOutcomeResult.Loss) {
                    // Bettors lost all
                    mmWin += mod.betAmount;
                } else if (mod.result == MarketOutcomeResult.HalfWin) {
                    // Bettors won half, other half is Void
                    // MM gets half the available returned, and should get half void once per market
                    halfVoid = true;
                    returnedAvailable = true;
                    mmReturn += mod.available / 2;
                    bettorToMmFees = mod.b2MmFee / 2;
                } else if (mod.result == MarketOutcomeResult.Win) {
                    // Bettors won all
                    returnedAvailable = true;
                    mmReturn += mod.available;
                    bettorToMmFees = mod.b2MmFee;
                }
            }
            // If there is a halfWin/halfLoss return half as void once
            if (halfVoid) mmReturn += sMarket.liquidity / 2;
            // If there is a Void or only a loss return half/full liquidity
            if (!returnedAvailable) mmReturn += (halfVoid ? sMarket.liquidity / 2 : sMarket.liquidity);
            sMarket.mmPaid = true;

            uint256 fp = _eventHandler.isOracleEvent(sMarket.eventHash) ? feePermilleOracleMM : feePermilleOwnMM;
            payout = mmWin + mmReturn;
            protoFees = mmWin * fp / 1000;
            transferMM = payout + bettorToMmFees - protoFees;
        }
        // Unlock the MMs proto fees
        ILockBox(_betBox).unlockAmountTo(marketHash, address(this), _token, protoFees);
        // Pay the proto fee
        _payFee(_betBox, feeReceiver, sMarket.owner, protoFees);
        // Update the balance according to this payout
        _attemptPayout(marketHash, payout);
        // Are all bettors and marketmaker settled/paid now?
        _checkAllPaid(marketHash);
        // Unlock regular payout and combined bettors fees
        IMarketmakerBox mmBox = IMarketmakerBox(_mmBoxFactory.marketmakerBoxes(sMarket.owner));
        ILockBox(_betBox).unlockAmountTo(marketHash, address(mmBox), _token, transferMM);
        // Pay the MM combined return from this market, and register in his mmBox
        mmBox.returnToOwner(transferMM);
        emit MarketmakerPayout(marketHash, sMarket.owner, transferMM, mmWin, mmReturn, bettorToMmFees, protoFees);
    }

    /**
     * @notice Pays the bettor of a market, assumes settle is done and data updated elsewhere.
     * @param bet is a struct of data identifying the bet details.
     * @return protoFees is the amount of fees paid by the bettor to the protocol.
     * @return b2mFees is the amount of fees paid by the bettor to the marketmaker.
     */
    function _payoutBettor(BetSettleData calldata bet) private returns (uint256 protoFees, uint256 b2mFees) {
        unchecked {
            MarketData storage sMarket = markets[bet.marketHash];
            protoFees = bet.win * feePermilleBettor / 1000;
            b2mFees = bet.win * sMarket.b2MmFeePermille/ 1000;
            // Update the balance according to this payot
            _attemptPayout(bet.marketHash, bet.payout);
            // Unlock the proto fees, Bethandler unlocks the payout.
            ILockBox(_betBox).unlockAmountTo(bet.marketHash, address(this), _token, protoFees);
            // Pay the proto fee, BetHandler pays the bettor
            _payFee(_betBox, feeReceiver, bet.bettor, protoFees);
        }
    }


    /**
     * @notice Check if an outcome exists for a specific market.
     * @param marketHash is the hash of the event to check.
     * @param outcomeId is the unique id of an outcome to check.
     * @return data of the matching outcome, if the outcome exist, reverts if not.
     */
    function _getOutcome(bytes32 marketHash, uint16 outcomeId) private view returns (MarketOutcomeData storage) {
        MarketData storage sMarket = markets[marketHash];
        for (uint i = 0; i < sMarket.outcomes.length; i++)
            if (sMarket.outcomes[i].outcomeId == outcomeId) return sMarket.outcomes[i];

        revert InvalidMarketOutcome({ marketHash: marketHash, outcomeId: outcomeId });
    }

    /**
     * @notice Check if an event for a market is completed and find the winning outcomeId.
     * @notice If the event is canceled/invalid it is considered completed and the market is void.
     * @param inMarket is the data of the market to check.
     * @return outcomeId the unique id of the winning outcome.
     * @return result is an enum of the unique id of the winning outcome.
     */
    function _getWinningOutcome(
        MarketData storage inMarket
    ) private view returns (uint16 outcomeId, MarketOutcomeResult result) {
        EventState state = _eventHandler.getEventState(inMarket.eventHash);
        if (state == EventState.Canceled || state == EventState.Invalid)
            return (kOutcome_Undefined, MarketOutcomeResult.Void);
        EventResult memory eventResult = _eventHandler.getEventResult(inMarket.eventHash);
        return getWinningOutcome(inMarket.marketType, inMarket.offset, eventResult);
    }

    /**
     * @notice Checks if this main handler is the processor of a specific market type.
     * @param inMarketType is the type of the market to check.
     * @return True if this is the processor of the market type, false if not.
     */
    function _isProcessor(uint32 inMarketType) private pure returns (bool) {
        if (inMarketType > kMarketType_Undefined && inMarketType <= kMarketType_MainHandlerMax) return true;
        return false;
    }
}
