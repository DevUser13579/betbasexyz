// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./interfaces/IMarketmakerFactory.sol";
import "./interfaces/IParlayMarketHandler.sol";
import "./interfaces/IMarketmakerBox.sol";
import "./interfaces/utils/ILockBox.sol";
import "./utils/TokenGating.sol";
import "./utils/FeeHandler.sol";
import "./constants/markets.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Parlay Market Handling
 * @author betBase community
 * @notice Contract for handling parlay markets, including storing data and firing chain events.
 * @notice This is a sub contract for the betBlox protocol.
 * @notice TokenGating is AccessHandler, AccessHandler is Initializable.
 */
contract ParlayMarketHandler is IParlayMarketHandler, TokenGating, FeeHandler {
    using TokenAmountValidator for address;

    // Dummy used to return zero data
    ParlayMarketOutcomeSetData noData;

    // parlay bet hash => parlay bet data
    mapping(bytes32 => ParlayBetData) private parlayBets;
    // parlay hash => parlay market data
    mapping(bytes32 => ParlayMarketData) private parlayMarkets;
    // bettor => parlay bet agent
    mapping(address => address) private _parlayAgents;
    uint256 private _hashCounter = 0;           // Used to create unique hashes.
    uint256 private _tokenMaxAmount;            // The maximum allowed token amount for liquidity, bets etc.
    uint256 private _maxBetOutcomeCount = 6;    // The max allowed outcomes for a parlay bet.
    uint256 private _maxMarketOutcomeCount = 6; // The max allowed outcomes for a parlay market.
    IEventHandler private _eventHandler;        // Address of the event handler that handles the event states/results.
    IMarketHandler private _marketHandler;      // Address of the market handler that handles market/outcome checks.
    IMarketmakerFactory private _mmBoxFactory;  // Address of the factory that makes all the marketMakerBoxes.
    address private _betBox;                    // Address of the bet box, where all tokens for markets are locked.

    /**
     * @dev Throws if called by any account other than the owner of a parlay market.
     * @param parlayHash is the hash of the parlay market to check.
     */
    modifier onlyOwner(bytes32 parlayHash) {
        if (parlayMarkets[parlayHash].mm != msg.sender)
            revert NotMarketOwner({parlayHash: parlayHash, add: msg.sender});
        _;
    }

    /**
     * @notice Default Constructor.
     */
    constructor() TokenGating() FeeHandler() {}

    /**
     * @notice Initializes this contract with reference to other contracts and set gating options.
     * @param inEventHandler The EventHandler contract address.
     * @param inMarketHandler The MarketHandler contract address.
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
    function init(
        address inEventHandler,
        address inMarketHandler,
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
        _setMarketHandler(inMarketHandler);
        _setMMBoxFactory(inMMBF);
        _initFees(inFeeReceiver, inFeePermilleBettor, inFeePermilleOracleMM, inFeePermilleOwnMM, inMaxFeePermille);
        _setGatingToken(inGatingToken);
        _setPresetGatingAmounts(inGatingAmount0, inGatingAmount1, inGatingAmount2);
        BaseInitializer.initialize();
    }

    /**
     * @notice Setter to change the max allowed outcomes for a parlay bet.
     * @param inCount is the new max value.
     */
    function setMaxBetOutcomes(uint8 inCount) external onlyRole(OPERATION_ADMIN_ROLE) {
        if (inCount < 2 || inCount > _maxMarketOutcomeCount)
            revert InvalidParlayOutcomeCount(_maxMarketOutcomeCount);
        emit SetMaxBetOutcomes(inCount);
        _maxBetOutcomeCount = inCount;
    }

    /**
     * @notice Setter to change the max allowed outcomes for a parlay market.
     * @param inCount is the new max value.
     */
    function setMaxMarketOutcomes(uint8 inCount) external onlyRole(OPERATION_ADMIN_ROLE) {
        // A parlay market should have at least the same amount of outcomes, as a bet can have.
        if (inCount < _maxBetOutcomeCount || inCount > MAX_PARLAY_COUNT)
            revert InvalidParlayOutcomeCount(MAX_PARLAY_COUNT);
        emit SetMaxMarketOutcomes(inCount);
        _maxMarketOutcomeCount = inCount;

    }

    /**
     * @notice Setter to change the parlay agent of a bettor.
     * @param inParlayAgent The new agent address, zero address if none.
     */
    function setParlayBetAgent(address inParlayAgent) external {
        emit SetParlayBetAgent(msg.sender, inParlayAgent);
        _parlayAgents[msg.sender] = inParlayAgent;
    }

    /**
     * @notice Adds a parlay market based on data in a single struct, approved by the marketmaker.
     * @notice Error is emitted if the parlay already exists or not allowed, events if success.
     * @param inputData is the hash of the event to add a market for.
     */
    function addParlayBet(ParlayBetInput calldata inputData) external {
        if (msg.sender != inputData.bettor) revert NotBettor({ add: inputData.bettor});
        _addParlayBet(inputData, ParlayBetType.Parley);
    }
    /**
     * @notice Adds a parlay market based on data in a single struct, approved by the marketmaker.
     * @notice Error is emitted if the parlay already exists or not allowed, events if success.
     * @param inputData is the hash of the event to add a market for.
     */
    function agentParlayBet(ParlayBetInput calldata inputData) external {
        if (_parlayAgents[inputData.bettor] != msg.sender) revert NotAgent({add: msg.sender});
        _addParlayBet(inputData, ParlayBetType.Agent);
    }

    /**
     * @notice Adds a parlay market based on data in a single struct, approved by the marketmaker.
     * @notice Error is emitted if the parlay already exists or not allowed, events if success.
     * @param liquidity is the amount of tokens the marketmaker has provided (laid) on the parlay market.
     * @param b2MmFeePermille is a parlay specific win fee rate, the bettor will pay to the marketmaker.
     * @param vipGroup a number between 0 and 255, that limits the access to who can bet. 0 means no VIP limitations.
     * @param outcomeSets is the list of outcome sets (markets) the marketmaker chose to offer as legs.
     */
     function addParlayMarket(
        uint256 liquidity,
        uint16 b2MmFeePermille,
        uint8 vipGroup,
        ParlayMarketOutcomeSetData[] calldata outcomeSets
    ) external hasMinBalance0 whenNotPaused {
        bytes32 parlayHash = keccak256(abi.encode("ParlayMarketHandler", msg.sender, ++_hashCounter));

        address mm = msg.sender;
        IMarketmakerBox mmBox = IMarketmakerBox(_mmBoxFactory.marketmakerBoxes(mm));
        if (address(mmBox) == ZERO_ADDRESS) revert NotMarketmaker(mm);

        // Store the parlay data
        ParlayMarketData storage sPM = parlayMarkets[parlayHash];
        sPM.parlayHash = parlayHash;
        sPM.mm = mm;
        sPM.vipGroup = vipGroup;
        sPM.b2MmFeePermille = b2MmFeePermille;
        sPM.liquidity = liquidity;
        sPM.available = liquidity;
        emit ParlayMarketAdded(parlayHash, mm, vipGroup, b2MmFeePermille, liquidity);

        if (liquidity == 0) revert InvalidParlayAmountInput();
        if (liquidity > _tokenMaxAmount) revert InvalidParlayAmountInput();
        _validateFeeToMM(b2MmFeePermille);

        uint256 len = outcomeSets.length;
        if (len < 2 || len > _maxMarketOutcomeCount) revert InvalidParlayOutcomeCount(_maxMarketOutcomeCount);
        for (uint256 i = 0; i < len; i++) {
            ParlayMarketOutcomeSetData memory ios = outcomeSets[i];
            // Checks if there is another os with same event/marketType
            if (_getOutcomeSet(sPM, ios.eventHash, ios.marketType).outcomes.length != 0)
                revert InvalidParlayMarketOutcomeSet(parlayHash, ios.eventHash, ios.marketType);

            ParlayMarketOutcomeSetData storage mos = sPM.outcomeSets.push();
            // Checks that event exists (checks type match) or creates it
            _eventHandler.checkOrAddEvent(ios.eventHash, ios.marketType, mm);
            // Checks offset value against market type
            if (!_marketHandler.isValidOffset(ios.marketType, ios.offset))
                revert InvalidParlayMarketOffsetInput(ios.marketType, ios.offset);
            uint16[] memory vo = _marketHandler.getValidOutcomes(ios.marketType);
            // Checks outcome id count
            if (vo.length != ios.outcomes.length) revert InvalidMarketOutcomesInput();

            mos.eventHash = ios.eventHash;
            mos.marketType = ios.marketType;
            mos.offset = ios.offset;
            for (uint8 j = 0; j < ios.outcomes.length; j++) {
                ParlayMarketOutcomeData memory iod = ios.outcomes[j];
                ParlayMarketOutcomeData storage mod = mos.outcomes.push();
                // Check ids
                if (iod.outcomeId != vo[j]) revert InvalidMarketOutcomesInput();
                // Check odds
                if (iod.odds <= ODDS_PRECISION || iod.odds > ODDS_PRECISION * MAX_ODDS)
                   revert InvalidParlayOddsInput();

                mod.outcomeId = iod.outcomeId;
                mod.odds = iod.odds;
                emit ParlayMarketOutcomeUpdated(
                    parlayHash,
                    ios.eventHash,
                    ios.marketType,
                    iod.odds,
                    iod.outcomeId
                );
            }
        }

         // Add the MMs token to the parlay (liquidity)
        mmBox.reserveForMarket(liquidity);
        // Lock in the bet box
        ILockBox(_betBox).lockAmount(parlayHash, _token, liquidity);
    }

    /**
     * @notice Adds additional liquidity for a parlay market.
     * @notice Revert Error is emitted if it fails.
     * @param parlayHash is the hash of the parlay market to update.
     * @param inAmount is the amount of bet tokens to add from the marketmaker.
     */
    function addLiquidity(bytes32 parlayHash, uint256 inAmount)
        external
        onlyOwner(parlayHash)
        hasMinBalance0
        whenNotPaused
    {
        ParlayMarketData storage sPM = parlayMarkets[parlayHash];
        address owner = msg.sender;

        // Add the MMs token to the parlay market
        IMarketmakerBox mmBox = IMarketmakerBox(_mmBoxFactory.marketmakerBoxes(owner));
        mmBox.reserveForMarket(inAmount);
        ILockBox(_betBox).lockAmount(parlayHash, _token, inAmount);
        unchecked {
            uint256 newBalance = inAmount + sPM.liquidity;
            if (newBalance > _tokenMaxAmount) revert InvalidParlayAmountInput();
            // Add to the liquidity and tokens available
            sPM.liquidity = newBalance;
            sPM.available += inAmount;
        }
        emit ParlayMarketLiquidityAdded(parlayHash, inAmount, sPM.liquidity);
    }

    /**
     * @notice Removes unused liquidity for a parlay market.
     * @notice Revert Error is emitted if incorrect owner or liquidity is not available.
     * @param parlayHash is the hash of the parlay market to update.
     * @param inAmount is the amount of bet tokens to return to the marketmaker.
     */
    function removeLiquidity(bytes32 parlayHash, uint256 inAmount)
        external
        onlyOwner(parlayHash)
        hasMinBalance0
        whenNotPaused
    {
        ParlayMarketData storage sPM = parlayMarkets[parlayHash];
        address owner = msg.sender;

        unchecked {
            // Decrease the tokens available for each outcome
            if (sPM.available < inAmount) {
                revert InsufficientParlayLiquidity({
                    parlayHash: parlayHash,
                    available: sPM.available,
                    required: inAmount
                });
            }
            // Decrease liquidity and tokens available
            sPM.available -= inAmount;
            sPM.liquidity -= inAmount;
        }
        // Unlock liquidity
        IMarketmakerBox mmBox = IMarketmakerBox(_mmBoxFactory.marketmakerBoxes(owner));
        ILockBox(_betBox).unlockAmountTo(parlayHash, address(mmBox), _token, inAmount);
        // Pay the MM and register in his mmBox
        mmBox.returnToOwner(inAmount);

        emit ParlayMarketLiquidityRemoved(parlayHash, inAmount, sPM.liquidity);
    }

    /**
     * @notice Changes the odds for a parlay market on a specific outcome.
     * @notice Revert Error is emitted if not owner or inputs are invalid.
     * @param parlayHash is the hash of the parlay market to update.
     * @param eventHash identifies the event for the outcome.
     * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
     * @param outcomeId is the outcome id of the outcome to update.
     * @param inOdds is the new odds value for the outcome.
     */
    function setOdds(
        bytes32 parlayHash,
        bytes32 eventHash,
        uint32 marketType,
        uint16 outcomeId,
        uint256 inOdds
    ) external onlyOwner(parlayHash) {
        ParlayMarketData storage sPM = parlayMarkets[parlayHash];
        if (inOdds <= ODDS_PRECISION || inOdds > ODDS_PRECISION * MAX_ODDS) {
            revert InvalidParlayOddsInput();
        }

        _eventHandler.assertEventIsActive(eventHash);
        // // Set the new odds value for the outcome
        ParlayMarketOutcomeData storage mod = _getOutcome(sPM, eventHash, marketType, outcomeId);
        mod.odds = inOdds;
        emit ParlayMarketOutcomeUpdated(parlayHash, eventHash, marketType, inOdds, outcomeId);
    }

    /**
     * @notice Settles a parlay market to prepare it for payouts and pays all bettors.
     * @notice Revert Error is emitted if not ready to settle.
     * @param parlayHash is the hash of the parlay market to settle.
     */
    function settleParlay(bytes32 parlayHash) external whenNotPaused {
        ParlayMarketData storage sPM = parlayMarkets[parlayHash];
        if (sPM.parlayHash == ZERO_HASH) revert InvalidParlayMarket({parlayHash: parlayHash});
        _settleParlay(sPM);
    }

    /**
     * @notice Settles and pays a parlay bet.
     * @notice Revert Error is emitted if not ready to settle.
     * @param parlayBetHash is the hash of the parlay bet to settle.
     */
    function payoutBettor(bytes32 parlayBetHash) external whenNotPaused {
        ParlayBetData storage sPB = parlayBets[parlayBetHash];
        if (parlayBets[parlayBetHash].parlayBetHash == ZERO_HASH)
            revert InvalidParlayBet({parlayBetHash: parlayBetHash});
        if (sPB.settled) {
            emit ParlayBetNoPayout(parlayBetHash, sPB.parlayMarketHash, sPB.bettor);
            return;
        }
        ParlayMarketData storage sPM = parlayMarkets[sPB.parlayMarketHash];
        // Settle the selected outcomes in the market
        for (uint256 i = 0; i < sPB.outcomes.length; i++) {
            ParlayBetOutcomeData storage bod = sPB.outcomes[i];
            _settleParlayOutcomeSet(sPM.parlayHash, _getOutcomeSet(sPM, bod.eventHash, bod.marketType));
        }
        _settleParlayBet(sPB);
    }

    /**
     * @notice Pays the marketmaker of a parlay market, settles first if necessary.
     * @notice Revert Error is emitted if not ready to settle/payout.
     * @param parlayHash is the hash of the parlay market to payout.
     */
    function payoutMarketmaker(bytes32 parlayHash) external whenNotPaused {
        ParlayMarketData storage sPM = parlayMarkets[parlayHash];
        if (sPM.parlayHash == ZERO_HASH) revert InvalidParlayMarket({parlayHash: parlayHash});
        if (sPM.mmPaid) revert InvalidParlayMarketState({parlayHash: parlayHash});
        _settleParlay(sPM);
        _payoutMarketmaker(sPM);
    }

    /**
     * @notice Changes the VIP group (0-255) for a parlay market. VIP roles for values 1-254 can be assigned.
     * @notice VIP group 0 is meant for unlimited access and 255 is for no access (betting disabled).
     * @notice Revert Error is emitted if not owner
     * @param parlayHash is the hash of the parlay market to update.
     * @param inGroup is the new VIP group value for the parlay market.
     */
    function setVIPGroup(bytes32 parlayHash, uint8 inGroup) external onlyOwner(parlayHash) {
        ParlayMarketData storage sPM = parlayMarkets[parlayHash];
        emit VIPGroupUpdated(parlayHash, inGroup, sPM.vipGroup);
        sPM.vipGroup = inGroup;
    }

    /**
     * @notice Get all data of a parlay bet.
     * @param parlayBetHash is the hash of the parlay bet to find.
     * @return ParlayBetData is the data, 0-data if the parlay bet does not exist.
     */
    function getParlayBetData(bytes32 parlayBetHash) external view returns (ParlayBetData memory) {
        return parlayBets[parlayBetHash];
    }

    /**
     * @notice Get all data of a parlay market.
     * @param parlayHash is the hash of the parlay market to find.
     * @return ParlayMarketData is the data, 0-data if the parlay market does not exist.
     */
    function getParlayMarketData(bytes32 parlayHash) external view returns (ParlayMarketData memory) {
        return parlayMarkets[parlayHash];
    }

    /**
     * @notice Get the event states of a parlay.
     * @param parlayHash is the hash of the parlay to investigate.
     * @return states is the event state array of the supplied parlay market.
     */
    function getEventStates(bytes32 parlayHash) external view returns (EventState[] memory states) {
        ParlayMarketData storage sPM = parlayMarkets[parlayHash];
        uint len = sPM.outcomeSets.length;
        states = new EventState[](len);
        for (uint i = 0; i < len; i++) {
            states[i] = _eventHandler.getEventState(sPM.outcomeSets[i].eventHash);
        }
    }

    /**
     * @notice Check an outcome exist for a specific parlay market.
     * @param parlayHash is the hash of the event to check.
     * @param eventHash identifies the event for the outome.
     * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
     * @param outcomeId is the outcome id of the outcome.
     * @return outcome is the matching outcome if it exists, reverts if not.
     */
    function getOutcome(
        bytes32 parlayHash,
        bytes32 eventHash,
        uint32 marketType,
        uint16 outcomeId
    ) external view returns (ParlayMarketOutcomeData memory outcome) {
        ParlayMarketData storage sPM = parlayMarkets[parlayHash];
        if (sPM.parlayHash == ZERO_HASH) revert InvalidParlayMarket({parlayHash: parlayHash});
        outcome = _getOutcome(sPM, eventHash, marketType, outcomeId);
    }

    /**
     * @dev Returns the address of the current owner of a parlay market.
     * @param parlayHash is the hash of the parlay market to look up.
     * @return The wallet address of the marketmaker.
     */
    function getOwner(bytes32 parlayHash) external view returns (address) {
        return parlayMarkets[parlayHash].mm;
    }

    /**
     * @notice Adds a parlay market based on data in a single struct, approved by the marketmaker.
     * @notice Error is emitted if the parlay already exists or not allowed, events if success.
     * @param inputData is the hash of the event to add a market for.
     * @param inType is the type of the parlay, e.g. regular parlay or agent.
     */
    function _addParlayBet(ParlayBetInput calldata inputData, ParlayBetType inType) private whenNotPaused {
        bytes32 parlayHash = keccak256(abi.encode(msg.sender, ++_hashCounter));
        // Checks that market exists
        ParlayMarketData storage sPM = parlayMarkets[inputData.parlayMarketHash];
        if (sPM.parlayHash == ZERO_HASH) revert InvalidParlayMarket({parlayHash: inputData.parlayMarketHash});
        // Checks VIP access
        if (sPM.vipGroup != 0) {
            IMarketmakerBox mmBox = IMarketmakerBox(_mmBoxFactory.marketmakerBoxes(sPM.mm));
            bytes32 role = keccak256(abi.encode(sPM.mm, sPM.vipGroup));
            if (!mmBox.hasRole(role, inputData.bettor)) revert NotVIP(sPM.parlayHash, inputData.bettor, sPM.vipGroup);
        }

        // Store the parlay bet data
        ParlayBetData storage sPB = parlayBets[parlayHash];
        sPB.parlayBetHash = parlayHash;
        sPB.parlayMarketHash = sPM.parlayHash;
        sPB.betAmount = inputData.betAmount;
        sPB.liquidity = _validateOddsAndAmounts(sPM.parlayHash, inputData.odds, sPM.available, inputData.betAmount);
        sPB.odds = inputData.odds;
        sPB.parlayType = inType;
        sPB.bettor = inputData.bettor;
        emit ParlayBetAdded(
            parlayHash,
            inputData.parlayMarketHash,
            inputData.bettor,
            inputData.betAmount,
            sPB.liquidity,
            inputData.odds,
            inType
        );

        uint256 len = inputData.outcomes.length;
        if (len < 2 || len > _maxBetOutcomeCount) revert InvalidParlayOutcomeCount(_maxBetOutcomeCount);
        // Check bettor balance and allowance
        inputData.bettor.checkAllowanceAndBalance(inputData.betAmount, _token, address(this));
        uint256 combinedOdds = ODDS_PRECISION;
        bytes32[] memory tmpArray = new bytes32[](len);
        for (uint256 i = 0; i < len; i++) {
            ParlayBetOutcomeData memory iod = inputData.outcomes[i];
            ParlayBetOutcomeData storage bod = sPB.outcomes.push();

            // Checks that event is active
            _eventHandler.assertEventIsActive(iod.eventHash);

            // Check that eventHash is unique for this parlay
            for (uint256 j = 0; j < i; j++) {
                if (tmpArray[j] == iod.eventHash) revert InvalidParlayDuplicateEventInput(iod.eventHash);
            }
            tmpArray[i] = iod.eventHash;

            // Store new bet outcome
            bod.eventHash = iod.eventHash;
            bod.odds = iod.odds;
            bod.marketType = iod.marketType;
            bod.outcomeId = iod.outcomeId;

            // calc combined odds, to compare with input value
            combinedOdds = combinedOdds * iod.odds / ODDS_PRECISION;
            // Check market odds and outcome id
            ParlayMarketOutcomeData storage mod = _getOutcome(sPM, iod.eventHash, iod.marketType, iod.outcomeId);
            if (mod.odds != iod.odds) revert InvalidParlayOddsInput();
            emit ParlayBetOutcomeAdded(parlayHash, iod.eventHash, iod.odds, iod.marketType, iod.outcomeId);
        }
        if (combinedOdds != inputData.odds) revert InvalidParlayOddsInput();
        unchecked {
            // Update parlay market
            sPM.betVolume += inputData.betAmount;
            sPM.available -= sPB.liquidity;
            sPM.betsWagered++;
            sPM.bets.push(parlayHash);
        } // unchecked

        // Lock in the bet box
        ILockBox(_betBox).lockAmount(inputData.parlayMarketHash, _token, inputData.betAmount);
        // // Add the bettors token to the parlay (betAmount)
        IERC20(_token).transferFrom(inputData.bettor, _betBox, inputData.betAmount);
    }

    /**
     * @notice Settles a parlay market to prepare it for payouts and pays all bettors.
     * @notice Revert Error is emitted if not ready to settle or outcome is undefined.
     * @param sPM is the data of the parlay market to settle.
     */
    function _settleParlay(ParlayMarketData storage sPM) private {
        if (sPM.settled) return;
        unchecked {
            for (uint256 i = 0; i < sPM.outcomeSets.length; i++)
                _settleParlayOutcomeSet(sPM.parlayHash, sPM.outcomeSets[i]);

            // Now settle and pay every bet
            for (uint256 i = 0; i < sPM.bets.length; i++)
                _settleParlayBet(parlayBets[sPM.bets[i]]);

            sPM.settled = true;
            emit ParlayMarketSettled(
                sPM.parlayHash,
                sPM.mm,
                sPM.liquidity + sPM.betVolume,
                sPM.betsWagered
            );
        } // unchecked
    }

    /**
     * @notice Settles and pays a parlay bet.
     * @notice Assumes the corresponding parlay market outcomes are already settled.
     * @notice Revert Error is emitted if not ready to settle.
     * @param sPB is the parlay bet data from storage used to settle.
     */
    function _settleParlayBet(ParlayBetData storage sPB) private {
        if (sPB.settled) return;
        ParlayMarketData storage sPM = parlayMarkets[sPB.parlayMarketHash];
        ParlayMarketOutcomeResult[] memory results = new ParlayMarketOutcomeResult[](sPB.outcomes.length);
        sPB.result = ParlayMarketOutcomeResult.Win;
        for (uint256 i = 0; i < sPB.outcomes.length; i++) {
            ParlayBetOutcomeData storage bod = sPB.outcomes[i];
            ParlayMarketOutcomeData storage mod = _getOutcome(sPM, bod.eventHash, bod.marketType, bod.outcomeId);
            results[i] = mod.result;
            if (mod.result == ParlayMarketOutcomeResult.Loss)
                sPB.result = ParlayMarketOutcomeResult.Loss;
            else if (sPB.result != ParlayMarketOutcomeResult.Loss && mod.result == ParlayMarketOutcomeResult.Void)
                sPB.result = ParlayMarketOutcomeResult.Void;
        }
        emit ParlayBetSettled(sPB.parlayBetHash, sPB.result, results);

        sPB.settled = true;
        sPM.betsSettled++;
        if (sPM.betsWagered == sPM.betsSettled) sPM.bettorsPaid = true;
        if (sPB.result == ParlayMarketOutcomeResult.Loss) {
            emit ParlayBetNoPayout(sPB.parlayBetHash, sPB.parlayMarketHash, sPB.bettor);
            return;
        }

        // Init values for Void and modify if the result is a Win
        uint256 bettorToMmFees;
        uint256 protoFees;
        uint256 payout = sPB.betAmount;
        uint256 transferBettor = payout;
        sPM.bettorReturns += payout;
        if (sPB.result == ParlayMarketOutcomeResult.Win) {
            bettorToMmFees = sPM.b2MmFeePermille * sPB.liquidity / 1000;
            protoFees = sPB.liquidity * feePermilleBettor / 1000;
            payout += sPB.liquidity;
            transferBettor = payout - bettorToMmFees - protoFees;

            sPM.bettorWins += sPB.liquidity;
            sPM.b2MmFees += bettorToMmFees;
            sPM.protoFees += protoFees;
        }

        _attemptPayout(sPM, payout);
        // Unlock the bettors return from this bet and the proto fees
        ILockBox(_betBox).unlockAmountTo(sPB.parlayMarketHash, address(this), _token, transferBettor + protoFees);
        // Pay the proto fee
        _payFee(_betBox, feeReceiver, sPB.bettor, protoFees);
        // Pay the bettor
        IERC20(_token).transferFrom(_betBox, sPB.bettor, transferBettor);
        emit BettorPayout(
            sPB.parlayBetHash,
            sPB.parlayMarketHash,
            sPB.bettor,
            transferBettor,
            payout - sPB.betAmount,
            sPB.betAmount,
            bettorToMmFees,
            protoFees
        );
    }

    /**
     * @notice Settles a parlay market outcome set to prepare it for payouts.
     * @notice Revert Error is emitted if not ready to settle or outcome is undefined.
     * @param parlayHash is the hash of the parlay market.
     * @param mos is the data of the parlay market outcome set to settle.
     */
    function _settleParlayOutcomeSet(bytes32 parlayHash, ParlayMarketOutcomeSetData storage mos) private {
        // Is this set already settled?
        if (mos.settled) return;

        uint outcomeLen = mos.outcomes.length;
        EventState state = _eventHandler.getEventState(mos.eventHash);
        ParlayMarketOutcomeResult[] memory results = new ParlayMarketOutcomeResult[](outcomeLen);
        // If canceled or Invalid, there is no event result, settle without
        if (state == EventState.Canceled || state == EventState.Invalid) {
            for (uint256 i = 0; i < outcomeLen; i++) {
                mos.outcomes[i].result = ParlayMarketOutcomeResult.Void;
                results[i] = ParlayMarketOutcomeResult.Void;
            }
        } else {
            // Get event result, and deduct outcome results.
            EventResult memory eventResult = _eventHandler.getEventResult(mos.eventHash);
            (uint16 winOutcomeId, MarketOutcomeResult result) =
                _marketHandler.getWinningOutcome(mos.marketType, mos.offset, eventResult);
            for (uint256 i = 0; i < outcomeLen; i++) {
                ParlayMarketOutcomeData storage outcome = mos.outcomes[i];
                if (
                    result == MarketOutcomeResult.Void ||
                    result == MarketOutcomeResult.HalfWin ||
                    result == MarketOutcomeResult.HalfLoss
                ) {
                    outcome.result = ParlayMarketOutcomeResult.Void;
                } else if (winOutcomeId != outcome.outcomeId || result != MarketOutcomeResult.Win) {
                    // Bettor didn't (fully) win this one, so we consider it a loss
                    outcome.result = ParlayMarketOutcomeResult.Loss;
                } else {
                    // Bettor fully won this one
                    outcome.result = ParlayMarketOutcomeResult.Win;
                }
                results[i] = outcome.result;
            } // for all outcomes
        }
        emit ParlayMarketOutcomeSetSettled(parlayHash, mos.eventHash, mos.marketType, results);
        mos.settled = true;
    }

    /**
     * @notice Pays the marketmaker of a parlay market, assumes settle is done.
     * @notice Revert Error is emitted if payout fails.
     * @param sPM is the data of the parlay market to payout.
     */
    function _payoutMarketmaker(ParlayMarketData storage sPM) private {
        bytes32 parlayHash = sPM.parlayHash;
        uint256 mmWin;
        uint256 mmReturn;
        uint256 payout;
        uint256 protoFees;
        uint256 transferMM;
        unchecked {
            // MM will get paid, what is left after bettor payouts.
            payout = sPM.liquidity + sPM.betVolume - sPM.paid;
            mmReturn = payout;
            if (sPM.liquidity < payout) {
                uint256 fp = feePermilleOwnMM;
                for (uint256 i = 0; i < sPM.outcomeSets.length; i++) {
                    if (_eventHandler.isOracleEvent(sPM.outcomeSets[i].eventHash)) {
                        fp = feePermilleOracleMM;
                        break;
                    }
                }
                mmReturn = sPM.liquidity;
                mmWin = payout - mmReturn;
                protoFees = mmWin * fp / 1000;
                // Unlock the MMs proto fees
                ILockBox(_betBox).unlockAmountTo(parlayHash, address(this), _token, protoFees);
                // Pay the proto fee
                _payFee(_betBox, feeReceiver, sPM.mm, protoFees);
                // Update the balance according to this payout
            }
            // MM receives return+win + bettor fees - proto fees
            transferMM = payout + sPM.b2MmFees - protoFees;
            sPM.protoFees += protoFees;
            sPM.mmPaid = true;
        }

        _attemptPayout(sPM, payout);
        // Unlock regular payout and combined bettors fees
        IMarketmakerBox mmBox = IMarketmakerBox(_mmBoxFactory.marketmakerBoxes(sPM.mm));
        ILockBox(_betBox).unlockAmountTo(parlayHash, address(mmBox), _token, transferMM);
        // Pay the MM combined return from this parlay market, and register in his mmBox
        mmBox.returnToOwner(transferMM);
        emit MarketmakerPayout(parlayHash, sPM.mm, transferMM, mmWin, mmReturn, sPM.b2MmFees, protoFees);
    }

    /**
     * @notice Tries to make a payout. Throws if attempt fails
     * @param sPM is the data of the parlay market to handle.
     * @param payout is the size of the requested payout.
     */
    function _attemptPayout(ParlayMarketData storage sPM, uint256 payout) private {
        if (payout == 0) return;
        unchecked {
            uint256 remainingAmount = sPM.liquidity + sPM.betVolume - sPM.paid;
            if (payout > remainingAmount) {
                revert InvalidParlayMarketPayout({
                    parlayHash: sPM.parlayHash,
                    requested: payout,
                    remaining: remainingAmount
                });
            }
            sPM.paid += payout;
        }
    }

    /**
     * @notice Check if odds and amount input for a parlay bet are valid.
     * @notice Error is emitted if some errors are encountered.
     * @param parlayMarketHash identifies the parlay market.
     * @param odds is the combined odds to check.
     * @param liquidity is the liquidity available in the market.
     * @param betAmount is the bet amount to bet.
     * @return matchAmount matched amount by the marketmaker.
     */
    function _validateOddsAndAmounts(bytes32 parlayMarketHash, uint256 odds, uint256 liquidity, uint256 betAmount)
        private
        view
        returns (uint256 matchAmount)
    {
        unchecked {
            matchAmount = betAmount * odds / ODDS_PRECISION - betAmount;
            if (odds <= ODDS_PRECISION || odds > ODDS_PRECISION * PARLAY_MAX_ODDS) revert InvalidParlayOddsInput();
            if (matchAmount > liquidity) revert InsufficientParlayLiquidity(parlayMarketHash, liquidity, matchAmount);
            if (betAmount == 0) revert InvalidParlayAmountInput();
            if (betAmount > _tokenMaxAmount) revert InvalidParlayAmountInput();
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
     * @notice Setter to change the referenced MarketHandler contract.
     * @param inMarketHandler The MarketHandler contract address.
     */
    function _setMarketHandler(address inMarketHandler) private {
        emit SetMarketHandler(inMarketHandler);
        _marketHandler = IMarketHandler(inMarketHandler);
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
     * @notice Check if an outcome set exists for a specific parlay market.
     * @param sPM is the data of the parlay market in storage to check for outcome set data.
     * @param eventHash identifies the event for the outcome.
     * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
     * @return set is the matching outcome set if it exists, reverts if not.
     */
    function _getOutcomeSet(
        ParlayMarketData storage sPM,
        bytes32 eventHash,
        uint32 marketType
    ) private view returns (ParlayMarketOutcomeSetData storage) {
        for (uint256 i = 0; i < sPM.outcomeSets.length; i++) {
            ParlayMarketOutcomeSetData storage mos = sPM.outcomeSets[i];
            if (mos.eventHash == eventHash && mos.marketType == marketType) return mos;
        }
        return noData;
    }

    /**
     * @notice Check if an outcome set exists for a specific parlay market.
     * @param sPM is the data of the parlay market in storage to check for outcome set data.
     * @param eventHash identifies the event for the outcome.
     * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
     * @param outcomeId is the outcome id of the outcome.
     * @return outcome is the matching outcome if it exists, reverts if not.
     */
    function _getOutcome(
        ParlayMarketData storage sPM,
        bytes32 eventHash,
        uint32 marketType,
        uint16 outcomeId
    ) private view returns (ParlayMarketOutcomeData storage) {
        ParlayMarketOutcomeSetData storage mos = _getOutcomeSet(sPM, eventHash, marketType);
        for (uint i = 0; i < mos.outcomes.length; i++) {
            ParlayMarketOutcomeData storage mod = mos.outcomes[i];
            if (mod.outcomeId == outcomeId) return mod;
        }

        revert InvalidParlayMarketOutcomeSet({
            parlayHash: sPM.parlayHash,
            eventHash: eventHash,
            marketType: marketType
        });
    }
}
