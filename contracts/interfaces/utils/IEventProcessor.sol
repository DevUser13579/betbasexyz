// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../IEventHandler.sol";

interface IEventProcessor {
    /**
     * @notice Error when trying to process an event with no configured processor.
     * @param eventType is the market type (unique id) to process.
     */
    error InvalidEventType(uint32 eventType);

    /**
     * @notice Error when trying to set an invalid result.
     * @param eventHash is the hash used to identify the event.
     * @param homeScore is the event score of the home team.
     * @param awayScore is the event score of the away team.
     * @param prediction is the outcome of a prediction event (0 if not a prediction).
     */
    error InvalidResult(bytes32 eventHash, uint16 homeScore, uint16 awayScore, uint8 prediction);

    /**
     * @notice Error when trying to pair an event type and market type, that does not match.
     * @param eventType is the event type (unique id) to pair.
     * @param marketType is the market type (unique id) to pair.
     */
    error BadEventMarketMatch(uint32 eventType, uint32 marketType);

    /**
     * @notice Check if a market type is valid for a specific event type.
     * @param inEventType is the type of the event to check.
     * @param inMarketType is the type of the market to check.
     * @return True if the market type is valid for the event type, false if not.
     */
    function isValidMarket(uint32 inEventType, uint32 inMarketType) external view returns (bool);

    /**
     * @notice Check if an event result is valid for a specific event type.
     * @notice Note: The check is not conclusive for type, a result of "0, 0, false" is valid for all event types.
     * @param inEventType is the type of the event to check.
     * @param inResult is the result data to check.
     * @return True if the result is valid for the event type, false if not.
     */
    function isValidResult(uint32 inEventType, EventResult calldata inResult) external view returns (bool);
}
