// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./IBetHandler.sol";
import "./IEventHandler.sol";
import "./utils/IMarketProcessor.sol";

enum MarketOutcomeResult { Undefined, Win, HalfWin, Void, HalfLoss, Loss } // Enum

/**
 * @notice Outcome data struct. An instance is used per allowed outcome in a market.
 * @param odds is the current odds as decimal-odds, offered by the marketMaker, to bet on this outcome.
 * @param available is the amount of the marketmakers volume, that is still available to bettors (unmatched).
 * @param betAmount is the combined amount betted by bettors in this outcome.
 * @param b2MmFee is the amount of fees the marketmaker will earn, if bettors win on this outcome.
 * @param betsWagered is the number of bets on this outcome by bettors.
 * @param betsSettled is the number of bets settled to the bettors combined, or to the mm if its a loss.
 * @param outcomeId is a number from 0 - 65535 to define the outcome, as seen from the bettor.
 *        Normally only a few are valid e.g. homeWin: 0, awayWin: 1.
 * @param result enum that defines if the result is a win, halfWin, loss etc., after the market is settled.
 */
struct MarketOutcomeData {
    uint256 odds;
    uint256 available;
    uint256 betAmount;
    uint256 b2MmFee;
    uint16 betsWagered;
    uint16 betsSettled;
    uint16 outcomeId;
    MarketOutcomeResult result;
}

/**
 * @notice Common market data struct.
 * @param eventHash identifies the corresponding event.
 * @param liquidity is the amount of tokens the marketmaker has provided (laid) on the market.
 * @param betVolume is the combined amount of tokens the bettors have bet (backed) on the market.
 * @param paid is the combined amount settled, to both marketmaker and bettors, ignoring fee details.
 * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
 * @param b2MmFeePermille is a market specific win fee rate, the bettors will pay to the marketmaker.
 * @param owner is the wallet address of the marketmaker, that "owns" this market.
 * @param vipGroup a number between 0 and 255, that limits the access to who can bet. 0 means no VIP limitations.
 * @param offset is a number value used for some market types like "totals-goals", "spread" etc.
 * @param settled is a boolean stating if the market has been settled (event results processed and payout ready).
 * @param mmPaid is stating if the marketmaker is paid yet.
 * @param bettorsPaid is stating if all bettors is paid yet.
 * @param outcomes is an array of structs holding all outcome related data.
 */
struct MarketData {
    bytes32 eventHash;
    uint256 liquidity;
    uint256 betVolume;
    uint256 paid;
    uint32 marketType;
    uint16 b2MmFeePermille;
    address owner;
    uint8 vipGroup;
    int32 offset; // signed integer with 2 decimals precission, to operate on .25, .5 and .75 values.
    bool settled;
    bool mmPaid;
    bool bettorsPaid;
    MarketOutcomeData[] outcomes;
}

/**
 * @param marketHash is the hash tyhat uniquely identifies the market.
 * @param bettor is the wallet address of the bettor.
 * @param outcomeId is the id uniquely defining the outcome type e.g. "homeWin".
 * @param payout is the amount to payout to the bettor before subtracting fees.
 * @param win is the amount won from the bet, the amount to calculate fees from.
 */
struct BetSettleData {
    bytes32 marketHash;
    address bettor;
    uint16 outcomeId;
    uint256 payout;
    uint256 win;
}

interface IMarketHandler is IMarketProcessor {
    /**
     * @notice Event that fires when the BetBox is set.
     * @param add is the new address.
     */
    event SetBetBox(address add);

    /**
     * @notice Event that fires when the EventHandler is set.
     * @param add is the new address.
     */
    event SetEventHandler(address add);

    /**
     * @notice Event that fires when the MarketmakerBoxFactory is set.
     * @param add is the new address.
     */
    event SetMarketmakerBoxFactory(address add);

    /**
     * @notice Event that fires when a market is added (initial state is Init).
     * @param marketHash is the hash used to identify the market.
     * @param eventHash is the hash the event connected to the market.
     * @param owner is the owner of this market (marketmaker), that is allowed to modify it.
     * @param marketType is the type of market, that defines, what types of markets are compatible.
     * @param b2MmFeePermille is a market specific win fee rate, the bettors will pay to the marketmaker.
     * @param vipGroup a number between 0 and 255, that limits the access to who can bet. 0 means no limitations.
     * @param offset is a number value used for some market types like "totals-goals", "spread" etc.
     */
    event MarketAdded(
        bytes32 indexed marketHash,
        bytes32 indexed eventHash,
        address indexed owner,
        uint32 marketType,
        uint16 b2MmFeePermille,
        uint8 vipGroup,
        int32 offset
    );

    /**
     * @notice Event that fires when odds are updated for an outcome.
     * @param marketHash is the hash used to identify the market.
     * @param odds is the odds offered by the owner on this outcome.
     * @param outcomeId is the id uniquely defining the outcome type e.g. "homeWin".
     */
    event MarketOutcomeUpdated(bytes32 indexed marketHash, uint256 odds, uint16 outcomeId);

    /**
     * @notice Event that fires when the VIP group is updated for a market.
     * @param marketHash is the hash used to identify the market.
     * @param vipGroup is the new group selected.
     * @param oldGroup is the previous vipGroup value.
     */
    event VIPGroupUpdated(bytes32 indexed marketHash, uint8 vipGroup, uint8 oldGroup);

    /**
     * @notice Event that fires when liquidity is added to a market, including the initial amount.
     * @param marketHash is the hash used to identify the market.
     * @param added is the amount of liquidity added.
     * @param liquidity is the new total amount of liquidity for this market.
     */
    event MarketLiquidityAdded(bytes32 indexed marketHash, uint256 added, uint256 liquidity);

    /**
     * @notice Event that fires when liquidity is removed from a market.
     * @param marketHash is the hash used to identify the market.
     * @param removed is the amount of liquidity removed.
     * @param liquidity is the new total amount of liquidity for this market.
     */
    event MarketLiquidityRemoved(bytes32 indexed marketHash, uint256 removed, uint256 liquidity);

    /**
     * @notice Event that fires when a market is settled.
     * @param marketHash is the hash used to identify the market.
     * @param outcomeId is the id uniquely defining the winning outcome type e.g. "homeWin".
     * @param result is an enum defining the winning result type e.g. Win, HalfWin, HalfLoss.
     * @param totalPool is the total amount staked in this market, by owner and bettors.
     */
    event MarketSettled(bytes32 indexed marketHash, uint16 outcomeId, MarketOutcomeResult result, uint256 totalPool);

    /**
     * @notice Event that fires when all market bets are settled and paid.
     * @param marketHash is the hash used to identify the market.
     * @param totalPool is the total amount staked in this market, by owner and bettors.
     * @param totalPaid is the total amount paid out to owner and bettors.
     * @param diff is the rounding diff transfered to the protocol fee receiver.
     */
    event MarketPaid(bytes32 indexed marketHash, uint256 totalPool, uint256 totalPaid, uint256 diff);

    /**
     * @notice Event that fires when the marketmaker is paid, after market settle.
     * @param marketHash is the hash used to identify the market.
     * @param owner is the owner of this market (marketmaker).
     * @param amountPaid is the amount paid/transfered to the marketmaker.
     * @param amountWon is the profit, from the bettors that lost.
     * @param amountReturned is the amount returned, after the bettors get their profit on the winning outcome.
     * @param amountFeesEarned is the fee amount from bettors earned on this market.
     * @param amountFeesProto is the fee amount paid to the protocol.
     */
    event MarketmakerPayout(
        bytes32 indexed marketHash,
        address indexed owner,
        uint256 amountPaid,
        uint256 amountWon,
        uint256 amountReturned,
        uint256 amountFeesEarned,
        uint256 amountFeesProto
    );

    /**
     * @notice Error when trying to access a market that does not exist.
     * @param marketHash is the hash used to identify the market.
     */
    error InvalidMarket(bytes32 marketHash);

    /**
     * @notice Error when trying to access a market that has the wrong state.
     * @param marketHash is the hash used to identify the market.
     */
    error InvalidMarketState(bytes32 marketHash);

    /**
     * @notice Error when trying to access a market outcome that does not exist.
     * @param marketHash is the hash used to identify the market.
     * @param outcomeId is the id uniquely defining an outcome type e.g. kOutcome_HomeWin.
     */
    error InvalidMarketOutcome(bytes32 marketHash, uint16 outcomeId);

    /**
     * @notice Error when trying to payout more than the remaining balance.
     * @param marketHash is the hash used to identify the market.
     * @param requested is the amount of tokens requested paid.
     * @param remaining is the the amount left to pay from, i.e. the full pot with the amounts paid subtracted.
     */
    error InvalidMarketPayout(bytes32 marketHash, uint256 requested, uint256 remaining);

    /**
     * @notice Error when trying to create/update a market with an invalid liquidity value.
     */
    error InvalidMarketLiquidityInput();

    /**
     * @notice Error when trying to create a market with an invalid market type.
     */
    error InvalidMarketTypeInput();

    /**
     * @notice Error when trying to create/update a market with an invalid outcome value.
     */
    error InvalidMarketOutcomesInput();

    /**
     * @notice Error when trying to create/update a market with an invalid odds value.
     */
    error InvalidMarketOddsInput();

    /**
     * @notice Error for Insufficient token liquidity for an operation.
     * @notice Needed `required` but only `available` available.
     * @param marketHash is the hash used to identify the market.
     * @param outcomeId is the id uniquely defining an outcome type e.g. kOutcome_HomeWin.
     * @param available balance available.
     * @param required requested amount to transfer.
     */
    error InsufficientLiquidity(
        bytes32 marketHash,
        uint16 outcomeId,
        uint256 available,
        uint256 required
    );

    /**
     * @notice Error when trying to add a market without being a MM (no MMbox).
     * @param add is the wallet address that made the violation.
     */
    error NotMarketmaker(address add);

    /**
     * @notice Error when trying to manage a market without ownership.
     * @param marketHash is the hash of the market.
     * @param add is the wallet/contract address that made the violation.
     */
    error NotMarketOwner(bytes32 marketHash, address add);

    /**
     * @notice Error when trying to bet on a market without the required VIP credentials.
     * @notice Note: VIP role 255 is never assigned to users, and can be used to temporarily prevent all betting.
     * @param marketHash is the hash of the market.
     * @param add is the wallet/contract address that made the violation.
     * @param vipGroup is a number between 1 and 255, representing the required vip group for betting.
     */
    error NotVIP(bytes32 marketHash, address add, uint8 vipGroup);

    function addBet(BetData calldata) external;
    function addMarket(bytes32, uint256, uint16, uint32, uint8, int32, uint256[] calldata) external;
    function addLiquidity(bytes32, uint256) external;
    function removeLiquidity(bytes32, uint256) external;
    function setOdds(bytes32, uint16, uint256) external;
    function payoutAll(BetSettleData[] calldata) external returns (uint256[] memory, uint256[] memory);
    function payoutBettor(BetSettleData calldata) external returns (uint256, uint256);
    function payoutMarketmaker(bytes32) external;
    function settleMarket(bytes32) external;
    function setVIPGroup(bytes32, uint8) external;

    function getMarketData(bytes32) external view returns (MarketData memory);
    function getEventState(bytes32) external view returns (EventState);
    function getOwner(bytes32) external view returns (address);
    function hasOutcome(bytes32, uint16) external view returns (bool);
    function getOutcome(bytes32, uint16) external view returns (MarketOutcomeData memory);
}
