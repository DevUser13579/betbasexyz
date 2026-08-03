// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./utils/IEventProcessor.sol";

// States are all possible, only Completed has a defined outcome.
enum EventState { Undefined, Init, Active, Playing, Completed, Canceled, Invalid } // Enum

// Result defined by final score.
struct EventResult {
    uint16 homeScore;  // Regular events with home/away team score
    uint16 awayScore;  // Regular events with home/away team score
    uint8 prediction;  // Prediction type events: 0 for undefined, 1-255 for outcomes (initially 1-5 used).
    string desc;       // Additional description that might be of interest. E.g. "Extended time final score: 120-100".
}

// Common event data struct.
struct EventData {
    // bytes32 eventHash;
    address owner;
    uint32 eventType;
    uint32 firstMarketType;
    EventState state;
    EventResult result;
}

interface IEventHandler is IEventProcessor {
    /**
     * @notice Event that fires when an event is added (initial state is Init).
     * @notice If its an uncontrolled event, it is immediately Activated and ownership is assigned.
     * @param eventHash is the hash used to identify the event.
     * @param firstMarketType is the type of market, that triggered the EventAdded event.
     */
    event EventAdded(bytes32 indexed eventHash, uint32 firstMarketType);

    /**
     * @notice Event that fires when an event is set active. During this event type and ownership is assigned.
     * @param eventHash is the hash used to identify the event.
     * @param owner is the owner of this event, that is allowed to modify it.
     * @param eventType is the type of event, that defines, what types of markets are compatible.
     * @param controlled indicates if this is an oracle controlled event or not.
     */
    event EventActive(bytes32 indexed eventHash, address indexed owner, uint32 eventType, bool controlled);

    /**
     * @notice Event that fires when an event is completed (settled).
     * @param eventHash is the hash used to identify the event.
     * @param result is the resulting score of the event.
     */
    event EventCompleted(bytes32 indexed eventHash, EventResult result);

    /**
     * @notice Event that fires when an event changes state.
     * @param eventHash is the hash used to identify the event.
     * @param newState is the new state of the event.
     * @param prevState is the previous state of the event.
     */
    event EventStateChanged(bytes32 indexed eventHash, EventState newState, EventState prevState);

    /**
     * @notice Error when trying to add an event that already exists.
     * @param eventHash is the hash of the existing event.
     */
    error DuplicateEvent(bytes32 eventHash);

    /**
     * @notice Error when trying to access an event that has the wrong state.
     * @param state is the actual state of the requested event.
     */
    error InvalidEventState(EventState state);

    /**
     * @notice Error when trying to manage an event without ownership.
     * @param eventHash is the hash of the event.
     * @param add is the wallet/contract address that made the violation.
     */
    error NotEventOwner(bytes32 eventHash, address add);

    function checkOrAddEvent(bytes32, uint32, address) external;
    function addEvent(bytes32, uint32) external;
    function setEventActive(bytes32, uint32) external;
    function setEventPlaying(bytes32) external;
    function cancelEvent(bytes32) external;
    function completeEvent(bytes32, EventResult calldata) external;
    function invalidateEvent(bytes32) external;

    function assertEventIsActive(bytes32) external view;
    function assertEventIsActiveOrPlaying(bytes32) external view;
    function getEventData(bytes32) external view returns (EventData memory);
    function getEventState(bytes32) external view returns (EventState);
    function getEventResult(bytes32) external view returns (EventResult memory);
    function isOracleEvent(bytes32) external view returns (bool);
    function owner(bytes32) external view returns (address);
}
