// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "../IEventHandler.sol";
import "../IMarketHandler.sol";

interface IMarketProcessor {
    /**
     * @notice Error when trying to process a market with no configured processor.
     * @param marketType is the market type (unique id) to process.
     */
    error InvalidMarketType(uint32 marketType);

    /**
     * @notice Error when trying add a market with an illegal offset.
     * @param marketType is the market type (unique id) to process.
     * @param offset is a number value used for some market types like "totals-goals", "spread" etc.
     */
    error InvalidOffset(uint32 marketType, int32 offset);

    /**
     * @notice Find the winning outcomeId for a market, based on the event result.
     * @param inMarketType is the type of the market to check.
     * @param inOffset is a number value used for some market types like "totals-goals", "spread" etc.
     * @param inResult is the result of the corresponding event.
     * @return outcomeId is the unique id of the winning outcome.
     * @return result is type of result, halfWin, loss, void etc.
     */
    function getWinningOutcome(
        uint32 inMarketType,
        int32 inOffset,
        EventResult memory inResult
    ) external view returns (uint16 outcomeId, MarketOutcomeResult result);

    /**
     * @notice Check if an outcomeId is valid for a specific marketType.
     * @param inMarketType is the type of the market to check.
     * @param inOutcomeId is the unique id of an outcome to check.
     * @return True if the outcome id is valid for the market type, false if not.
     */
    function isValidOutcome(uint32 inMarketType, uint16 inOutcomeId) external view returns (bool);

    /**
     * @notice Implements IMarketProcessor.
     * @notice Get all valid outcomeId for a specific marketType.
     * @param inMarketType is the type of the market to check.
     * @return outcomes is the list of matching outcomeId.
     */
    function getValidOutcomes(uint32 inMarketType) external view returns (uint16[] memory outcomes);

    /**
     * @notice Check if an offset is valid for a specific marketType.
     * @param inMarketType is the type of the market to check.
     * @param inOffset is a number value used for some market types like "totals-goals", "spread" etc.
     * @return True if the offset is valid for the market type, false if not.
     */
    function isValidOffset(uint32 inMarketType, int32 inOffset) external view returns (bool);
}
