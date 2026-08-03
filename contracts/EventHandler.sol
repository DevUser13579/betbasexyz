// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./interfaces/IEventHandler.sol";
import "./utils/TokenGating.sol";
import "./utils/ProcessorHandler.sol";
import "./constants/events.sol";
import "./constants/markets.sol";

/**
 * @title Event Handling
 * @author betBase community
 * @notice Contract for handling events, including storing data and firing chain events.
 * @notice This is a sub contract for the betBlox protocol.
 * @notice TokenGating is AccessHandler, AccessHandler is Initializable.
 */
contract EventHandler is IEventHandler, TokenGating, ProcessorHandler {
    // event hash => event data
    mapping(bytes32 => EventData) private events;

    /**
     * @dev Throws if called by any account other than the owner of an event.
     * @param eventHash is the hash of the event to check.
     */
    modifier onlyOwner(bytes32 eventHash) {
        _checkOwner(eventHash);
        _;
    }

    /**
     * @notice Default Constructor.
     */
    constructor() TokenGating() {}

    /**
     * @notice Initializes this contract with reference to other contracts and set gating options.
     * @param inGatingToken The token to check balance for.
     * @param inGatingAmount0 Is preset amount 0 to use as balance requirement.
     * @param inGatingAmount1 Is preset amount 1 to use as balance requirement.
     * @param inGatingAmount2 Is preset amount 2 to use as balance requirement.
     */
    function initWithGating(
        address inGatingToken,
        uint256 inGatingAmount0,
        uint256 inGatingAmount1,
        uint256 inGatingAmount2
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setGatingToken(inGatingToken);
        _setPresetGatingAmounts(inGatingAmount0, inGatingAmount1, inGatingAmount2);
        BaseInitializer.initialize();
    }

    /**
     * @notice Initializes this contract with reference to other contracts.
     */
    function init() external onlyRole(DEFAULT_ADMIN_ROLE) {
        BaseInitializer.initialize();
    }

    /**
     * @notice Checks if a matching event exists for a new market.
     * @notice If found and Active, the eventType/marketType match is checked.
     * @notice If the event does not yet exist, it is added as an oracle controlled event.
     * @notice If added, it remains in Init state until Oracle takes ownership and sets an eventType.
     * @notice Error is emitted if the event already exists but market does not match or if add is not allowed.
     * @notice Restrictions are made based on assigned Markets Role (only MarketHandler has permission).
     * @param eventHash is the hash of the event to add.
     * @param marketType is the type of the triggering market as an id.
     * @param marketmaker is the MM that is adding a new market.
     */
    function checkOrAddEvent(
        bytes32 eventHash,
        uint32 marketType,
        address marketmaker
    ) external onlyRole(MARKETS_ROLE) {
        EventState existingEventState = events[eventHash].state;
        if (existingEventState == EventState.Undefined) {
            _addEvent(eventHash, marketType);
        } else if (existingEventState == EventState.Active) {
            EventData storage eventData = events[eventHash];
            address eventOwner = eventData.owner;
            // Owner should either be the MM that owns this, or it should be an Oracle (controlled) event.
            if (eventOwner != marketmaker && !hasRole(ORACLE_ROLE, eventOwner))
                revert NotEventOwner(eventHash, marketmaker);
            if (!isValidMarket(eventData.eventType, marketType))
                revert BadEventMarketMatch(eventData.eventType, marketType);
        }
        else {
            revert InvalidEventState({state: existingEventState});
        }
    }

    /**
     * @notice Adds a marketmaker controlled event, based on a hash.
     * @notice The event is immediately assigned a type and set Active, and is ready for getting markets added.
     * @notice Error is emitted if the event already exists or not allowed, Events are emitted if success.
     * @notice Restrictions are made based on gating token balance.
     * @param eventHash is the hash of the event to add.
     * @param eventType is the type of the event as an id.
     */
    function addEvent(bytes32 eventHash, uint32 eventType) external hasMinBalance0 whenNotPaused {
        _addEvent(eventHash, kMarketType_Undefined);
        _activateEvent(eventHash, eventType);
    }

    /**
     * @notice Updates an event to Active state. Oracle calls this to acknowledge this events.
     * @notice This update is triggered from the creation of a new market. If the eventType/marketType match
     * @notice does not match, this Event must remain unused, or the market Canceled, before the Event is set Active.
     * @notice Revert Error is emitted if not exist.
     * @param eventHash is the hash of the event to update.
     * @param eventType is the type of the event as an id.
     */
    function setEventActive(bytes32 eventHash, uint32 eventType) external onlyRole(ORACLE_ROLE) {
        _activateEvent(eventHash, eventType);
    }

    /**
     * @notice Updates an event to Playing state.
     * @notice Revert Error is emitted if not exist.
     * @param eventHash is the hash of the event to update.
     */
    function setEventPlaying(bytes32 eventHash) external onlyOwner(eventHash) whenNotPaused {
        // Checks that it is active
        EventState state = events[eventHash].state;
        if (state != EventState.Active) revert InvalidEventState({state: events[eventHash].state});

        emit EventStateChanged(eventHash, EventState.Playing, state);
        events[eventHash].state = EventState.Playing;
    }

    /**
     * @notice Updates an event to Completed state and sets a result.
     * @notice Revert Error is emitted if not in playing state.
     * @param eventHash is the hash of the event to update.
     * @param result is the result of event, the score of the 2 contestants.
     */
    function completeEvent(bytes32 eventHash, EventResult calldata result)
        external
        onlyOwner(eventHash)
        whenNotPaused
    {
        // Checks that it is Active or Playing
        assertEventIsActiveOrPlaying(eventHash);
        // Assert that the result is valid
        _assertValidResult(eventHash, result);

        EventState state = events[eventHash].state;
        emit EventStateChanged(eventHash, EventState.Completed, state);
        events[eventHash].state = EventState.Completed;
        events[eventHash].result = result;
        emit EventCompleted(eventHash, result);
    }

    /**
     * @notice Updates an event to Canceled state. Markets will resolve as void.
     * @notice Revert Error is emitted if not exist or invalid.
     * @param eventHash is the hash of the event to update.
     */
    function cancelEvent(bytes32 eventHash) external whenNotPaused {
        // Checks that it exists and is not Completed
        EventState state = events[eventHash].state;
        if (state == EventState.Undefined || state == EventState.Completed || state == EventState.Invalid)
            revert InvalidEventState({state: state});

        // If there is an owner, it should be the caller, if not check for Oracle role
        if (owner(eventHash) != ZERO_ADDRESS) _checkOwner(eventHash);
        else _checkRole(ORACLE_ROLE);

        emit EventStateChanged(eventHash, EventState.Canceled, state);
        events[eventHash].state = EventState.Canceled;
    }

    /**
     * @notice Updates an event to Invalid state. Primarily used to stop events that never got in Active state in time.
     * @notice Revert Error is emitted if not exist or invalid.
     * @param eventHash is the hash of the event to update.
     */
    function invalidateEvent(bytes32 eventHash) external whenNotPaused {
        // Checks that it exists and is not Completed
        EventState state = events[eventHash].state;
        if (state == EventState.Undefined || state == EventState.Completed || state == EventState.Canceled)
            revert InvalidEventState({state: state});

        // If there is an owner, it should be the caller, if not check for Oracle role
        if (owner(eventHash) != ZERO_ADDRESS) _checkOwner(eventHash);
        else _checkRole(ORACLE_ROLE);

        emit EventStateChanged(eventHash, EventState.Invalid, state);
        events[eventHash].state = EventState.Invalid;
    }

    /**
     * @notice Check if event exists and is active.
     * @notice Errors are emitted if check fails.
     * @param eventHash is the hash of the event to check.
     */
    function assertEventIsActive(bytes32 eventHash) external view {
        EventState state = events[eventHash].state;
        if (state != EventState.Active) revert InvalidEventState({state: state});
    }

    /**
     * @notice Get all data of an event.
     * @param eventHash is the hash of the event to find.
     * @return EventData is the data.
     */
    function getEventData(bytes32 eventHash) external view returns (EventData memory) {
        return events[eventHash];
    }

    /**
     * @notice Get an event state.
     * @param eventHash is the hash of the event to find.
     * @return EventState is the state of the supplied event.
     */
    function getEventState(bytes32 eventHash) external view returns (EventState) {
        return events[eventHash].state;
    }

    /**
     * @notice Get an event result, revert if it does not exist or is not ready.
     * @param eventHash is the hash of the event to find.
     * @return EventResult is the result of the supplied event.
     */
    function getEventResult(bytes32 eventHash) external view returns (EventResult memory) {
        EventState state = events[eventHash].state;
        if (state != EventState.Completed) revert InvalidEventState({state: state});
        return events[eventHash].result;
    }


    /**
     * @notice Check the owner of an event, report if it is Oracle controlled.
     * @param eventHash is the hash of the event to check.
     * @return bool true is it is Oracle controlled, false if not.
     */
    function isOracleEvent(bytes32 eventHash) external view returns (bool) {
        EventState state = events[eventHash].state;
        if (state == EventState.Undefined) revert InvalidEventState({state: state});
        return hasRole(ORACLE_ROLE, events[eventHash].owner);
    }

    /**
     * @notice Check if event exists and is active or playing.
     * @notice Errors are emitted if check fails.
     * @param eventHash is the hash of the event to check.
     */
    function assertEventIsActiveOrPlaying(bytes32 eventHash) public view {
        EventState state = events[eventHash].state;
        if (state != EventState.Active && state != EventState.Playing) revert InvalidEventState({state: state});
    }

    /**
     * @dev Returns the address of the current owner of an event.
     * @param eventHash is the hash of the event to look up.
     */
    function owner(bytes32 eventHash) public view returns (address) {
        return events[eventHash].owner;
    }

    /**
     * @notice Implements IEventProcessor.
     * @notice Check if a market type is valid for a specific event type.
     * @param inEventType is the type of the event to check.
     * @param inMarketType is the type of the market to check.
     * @return True if the market type is valid for the event type, false if not.
     */
    function isValidMarket(uint32 inEventType, uint32 inMarketType) public view returns (bool) {
        address proc = _processors[inEventType];
        if (proc != ZERO_ADDRESS) {
            // An external processor is registered
            return IEventProcessor(proc).isValidMarket(inEventType, inMarketType);
        }
        if (_isProcessor(inEventType)) {
            // Process here instead
            if (inEventType >= kEventType_Basketball && inEventType < kEventType_MMA) {
                // Process US sports types with Moneyline, Spread and Total markets.
                return (inMarketType >= kMarketType_MoneyLine && inMarketType <= kMarketType_MoneyLine_Away) ||
                    (inMarketType >= kMarketType_Spread && inMarketType <= kMarketType_Spread_2) ||
                    (inMarketType >= kMarketType_Total && inMarketType <= kMarketType_Total_Under);
            } else if (inEventType >= kEventType_MMA && inEventType < kEventType_Soccer) {
                // Process sports types with only Moneyline markets.
                return (inMarketType >= kMarketType_MoneyLine && inMarketType <= kMarketType_MoneyLine_Away);
            } else if (inEventType >= kEventType_Soccer && inEventType <= kEventType_MainHandlerSportMax) {
                // Process sports types with FulltimeResult, Asian/Spread and Total markets.
                return (inMarketType >= kMarketType_FulltimeResult && inMarketType <= kMarketType_FulltimeResult_2) ||
                    (inMarketType >= kMarketType_Spread && inMarketType <= kMarketType_Spread_2) ||
                    (inMarketType >= kMarketType_Total && inMarketType <= kMarketType_Total_Under);
            } else if (inEventType >= kEventType_Prediction && inEventType <= kEventType_MainHandlerMax) {
                // Prediction events, allow the 5 prediction market types
                return (inMarketType >= kMarketType_Prediction1 && inMarketType <= kMarketType_Prediction5);
            }
            return false;
        } else {
            revert InvalidEventType(inEventType);
        }
    }

    /**
     * @notice Implements IEventProcessor.
     * @notice Check if an event result is valid for a specific event type, but event type only.
     * @notice The check is not conclusive, as a result of "0, 0, 4" is valid for prediction event types,
     *         but not a kMarketType_Prediction2 market.
     * @param inEventType is the type of the event to check.
     * @param inResult is the result data to check.
     * @return True if the result is valid for the event type, false if not.
     */
    function isValidResult(uint32 inEventType, EventResult calldata inResult) public view returns (bool) {
        address proc = _processors[inEventType];
        if (proc != ZERO_ADDRESS) {
            // An external processor is registered
            return IEventProcessor(proc).isValidResult(inEventType, inResult);
        }
        if (_isProcessor(inEventType)) {
            // Process here instead
            if (inEventType >= kEventType_Basketball && inEventType < kEventType_MMA) {
                // Process US sports types with Moneyline, Spread and Total markets.
                // Check that scores are in 0 - 10,000 interval and prediction is 0.
                return inResult.homeScore <= MAX_SCORE && inResult.awayScore <= MAX_SCORE && inResult.prediction == 0;
            } else if (inEventType >= kEventType_MMA && inEventType < kEventType_Soccer) {
                // Process sports types with only Moneyline markets.
                // Check that scores are in 0 - 10,000 interval and prediction is 0.
                return inResult.homeScore <= MAX_SCORE && inResult.awayScore <= MAX_SCORE && inResult.prediction == 0;
            } else if (inEventType >= kEventType_Soccer && inEventType <= kEventType_MainHandlerSportMax) {
                // Process sports types with FulltimeResult, Asian/Spread and Total markets.
                // Check that scores are in 0 - 10,000 interval and prediction is 0.
                return inResult.homeScore <= MAX_SCORE && inResult.awayScore <= MAX_SCORE && inResult.prediction == 0;
            } else if (inEventType >= kEventType_Prediction && inEventType <= kEventType_MainHandlerMax) {
                // Prediction events
                // Check that scores are 0, prediction can be 1-5.
                return
                    inResult.homeScore == 0 &&
                    inResult.awayScore == 0 &&
                    inResult.prediction > 0 &&
                    inResult.prediction <= 5;
            }
            return false;
        } else {
            revert InvalidEventType(inEventType);
        }
    }

    /**
     * @notice Adds an event, based on a hash.
     * @param eventHash is the hash of the event to add.
     * @param firstMarketType is the type of the market that triggered the addEvent (if an Oracle controlled event).
     * @notice Error is emitted if the event already exists, Event if not.
     */
    function _addEvent(bytes32 eventHash, uint32 firstMarketType) private {
        // Checks that it does not exist already
        EventState existingEventState = events[eventHash].state;
        if (existingEventState != EventState.Undefined) revert DuplicateEvent({eventHash: eventHash});

        emit EventStateChanged(eventHash, EventState.Init, EventState.Undefined);
        events[eventHash].state = EventState.Init;
        events[eventHash].firstMarketType = firstMarketType;
        emit EventAdded(eventHash, firstMarketType);
    }

    /**
     * @notice Activates an event, based on a hash, and sets the event type.
     * @notice Error is emitted if the event already exists, Event if not.
     */
    function _activateEvent(bytes32 eventHash, uint32 eventType) private {
        // Checks that it does not exist already
        EventData storage evt = events[eventHash];
        if (evt.state != EventState.Init) revert InvalidEventState({state: evt.state});
        if (evt.firstMarketType != kMarketType_Undefined && !isValidMarket(eventType, evt.firstMarketType))
            revert BadEventMarketMatch(eventType, evt.firstMarketType);

        emit EventStateChanged(eventHash, EventState.Active, EventState.Init);
        events[eventHash].owner = msg.sender;
        events[eventHash].eventType = eventType;
        events[eventHash].state = EventState.Active;
        emit EventActive(eventHash, msg.sender, eventType, hasRole(ORACLE_ROLE, msg.sender));
    }

    /**
     * @notice Checks if the sender is the owner of an event. Throws if check fails.
     * @param eventHash is the hash of the event to check.
     */
    function _checkOwner(bytes32 eventHash) private view {
        if (owner(eventHash) != msg.sender) revert NotEventOwner({eventHash: eventHash, add: msg.sender});
    }

    /**
     * @notice Checks if this main handler is the processor of a specific event type.
     * @param inEventType is the type of the event to check.
     * @return True if this is the processor of the event type, false if not.
     */
    function _isProcessor(uint32 inEventType) private pure returns (bool) {
        if (inEventType > kEventType_Undefined && inEventType <= kEventType_MainHandlerMax) return true;
        return false;
    }

    /**
     * @notice Check if an event result is valid for a specific event type. Throw error if not.
     * @param inEventHash  is the hash that represents the event to check.
     * @param inResult is the result data to check.
     */
    function _assertValidResult(bytes32 inEventHash, EventResult calldata inResult) private view {
        if (!isValidResult(events[inEventHash].eventType, inResult)) {
            revert InvalidResult({
                eventHash: inEventHash,
                homeScore: inResult.homeScore,
                awayScore: inResult.awayScore,
                prediction: inResult.prediction
            });
        }
    }
}
