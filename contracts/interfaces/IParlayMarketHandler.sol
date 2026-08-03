// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./IMarketHandler.sol";
import "./IEventHandler.sol";

// Types are all possible, Undefined means not existing parlay bet.
enum ParlayBetType { Undefined, Parley, Agent } // Enum
enum ParlayMarketOutcomeResult { Undefined, Win, Void, Loss } // Enum

/**
 * @notice Outcome data struct. An instance is used per selected event and outcome in a parlay.
 * @notice The outcome data uses MarketHandler defined types and ids, to be able to use MarketHandler functions.
 * @notice Parlay bet data is not related to any created markets in MarketHandler though.
 * @param eventHash identifies the event for this outcome.
 * @param odds is the agreed odds as decimal-odds, for this outcome.
 * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
 * @param outcomeId is a number from 0 - 65535 to define the outcome, as seen from the bettor.
 */
struct ParlayBetOutcomeData {
    bytes32 eventHash;
    uint256 odds;
    uint32 marketType;
    uint16 outcomeId;
}

/**
 * @notice Common parlay bet data struct.
 * @param parlayBetHash identifies this parlay bet.
 * @param parlayMarketHash identifies the parlay market.
 * @param betAmount is the amount of tokens the bettor has bet (backed) on the parlay.
 * @param liquidity is the amount of tokens the marketmaker has matched (laid) on the bet.
 * @param odds is the agreed odds as decimal-odds, combined for all outcomes.
 * @param parlayType is the type of the parlay, e.g. regular parlay or agent.
 * @param bettor is the wallet address of the bettor.
 * @param settled is a boolean stating if the parlay bet has been settled.
 * @param result enum that defines if the result is a win, loss etc., after the parlay is settled.
 * @param outcomes is an array of structs holding all outcome related data.
 */
struct ParlayBetData {
    bytes32 parlayBetHash;
    bytes32 parlayMarketHash;
    uint256 betAmount;
    uint256 liquidity;
    uint256 odds;
    ParlayBetType parlayType;
    address bettor;
    bool settled;
    ParlayMarketOutcomeResult result;
    ParlayBetOutcomeData[] outcomes;
}

/**
 * @notice This is a subset of ParlayBetData used to create a parlay bet.
 */
struct ParlayBetInput {
    bytes32 parlayMarketHash;
    uint256 betAmount;
    uint256 odds;
    ParlayBetType parlayType;
    address bettor;
    ParlayBetOutcomeData[] outcomes;
}

/**
 * @notice Outcome data struct. An instance is used per outcome in an outcome set.
 * @notice E.g. 2 separate instances in a kMarketType_MoneyLine set, 1 in a kMarketType_MoneyLine_Home set.
 * @notice The data uses MarketHandler defined types and ids, to be able to use MarketHandler functions.
 * @notice Parlay data is not related to any created markets in MarketHandler though.
 * @param outcomeId is a number from 0 - 65535 to define the outcome, as seen from the bettor.
 *        This outcome id is for the individual outcome, not the combined parlay market.
 * @param result enum that defines if the result is a win, loss or void, after the parlay market is settled.
 *        This result is for the individual outcome, not the combined parlay market.
 * @param odds is the current odds as decimal-odds, offered by the marketMaker, to bet on this outcome.
 */
struct ParlayMarketOutcomeData {
    uint16 outcomeId;
    ParlayMarketOutcomeResult result;
    uint256 odds;
}

/**
 * @notice Outcome set data struct. An instance is used per selected event and market type in a parlay market.
 * @notice The data uses MarketHandler defined types and ids, to be able to use MarketHandler functions.
 * @notice Parlay data is not related to any created markets in MarketHandler though.
 * @param eventHash identifies the event for this outcome set.
 * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
 * @param offset is a number value used for some market types like "totals-goals", "spread" etc.
 * @param settled is a boolean stating if this outcome set has been settled.
 * @param outcomes is an array of structs holding all individual outcome data.
 */
struct ParlayMarketOutcomeSetData {
    bytes32 eventHash;
    uint32 marketType;
    int32 offset; // signed integer with 2 decimals precission, to operate on .25, .5 and .75 values.
    bool settled;
    ParlayMarketOutcomeData[] outcomes;
}

/**
 * @notice Common parlay data struct.
 * @param parlayHash identifies this parlay market.
 * @param liquidity is the amount of tokens the marketmaker has provided (laid) on the parlay market.
 * @param available is the amount of the marketmakers volume, that is still available to bettors (unmatched).
 * @param betVolume is the total amount of tokens the bettors has bet (backed) on the parlay market.
 * @param bettorWins is the combined amount won by bettors, ignoring fee details.
 * @param bettorReturns is the combined amount returned to bettors, without paying fees.
 * @param protoFees is the combined fee amount paid by bettors and marketmaker to the protocol.
 * @param b2MmFees is the combined fee amount paid by bettors to the marketmaker.
 * @param paid is the combined amount paid, to both marketmaker and bettors, ignoring fee details.
 * @param b2MmFeePermille is a parlay specific win fee rate, the bettor will pay to the marketmaker.
 * @param mm is the wallet address of the marketmaker, that created this parlay.
 * @param vipGroup a number between 0 and 255, that limits the access to who can bet. 0 means no VIP limitations.
 * @param betsWagered is the number of bets on this parlay market by bettors.
 * @param betsSettled is the number of bets settled for this parlay market.
 * @param settled is a boolean stating if the full parlay market has been settled.
 * @param bets is a list of bet hashes for all bets made on this market.
 * @param outcomeSets is an array of structs holding all outcome set related data (common market data).
 */
struct ParlayMarketData {
    bytes32 parlayHash;
    uint256 liquidity;
    uint256 available;
    uint256 betVolume;
    uint256 bettorWins;
    uint256 bettorReturns;
    uint256 b2MmFees;
    uint256 protoFees;
    uint256 paid;
    uint16 b2MmFeePermille;
    address mm;
    uint8 vipGroup;
    uint16 betsWagered;
    uint16 betsSettled;
    bool settled;
    bool mmPaid;
    bool bettorsPaid;
    bytes32[] bets;
    ParlayMarketOutcomeSetData[] outcomeSets;
}

interface IParlayMarketHandler {
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
     * @notice Event that fires when the MarketHandler is set.
     * @param add is the new address.
     */
    event SetMarketHandler(address add);

    /**
     * @notice Event that fires when the MarketmakerBoxFactory is set.
     * @param add is the new address.
     */
    event SetMarketmakerBoxFactory(address add);

    /**
     * @notice Event that fires when a parlay market is added.
     * @param parlayHash identifies this parlay bet.
     * @param mm is the wallet address of the marketmaker, that created this parlay.
     * @param vipGroup a number between 0 and 255, that limits the access to who can bet. 0 means no VIP limitations.
     * @param b2MmFeePermille is a parlay specific win fee rate, the bettor will pay to the marketmaker.
     * @param liquidity is the amount of tokens the marketmaker has provided (laid) on the parlay.
     */
    event ParlayMarketAdded(
        bytes32 indexed parlayHash,
        address indexed mm,
        uint8 vipGroup,
        uint16 b2MmFeePermille,
        uint256 liquidity
    );

    /**
     * @notice Event that fires when odds are updated for an outcome.
     * @param parlayHash is the hash used to identify the parlay market.
     * @param eventHash identifies the corresponding event.
     * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
     * @param odds is the odds offered by the owner on this outcome.
     * @param outcomeId is the id uniquely defining the outcome type e.g. "homeWin".
     */
    event ParlayMarketOutcomeUpdated(
        bytes32 indexed parlayHash,
        bytes32 indexed eventHash,
        uint32 marketType,
        uint256 odds,
        uint16 outcomeId
    );

    /**
     * @notice Event that fires when a parlay bet is added.
     * @param parlayBetHash identifies this parlay bet.
     * @param parlayMarketHash identifies the parlay market.
     * @param bettor is the wallet address of the bettor.
     * @param betAmount is the amount of tokens the bettor has bet (backed) on the parlay.
     * @param liquidity is the amount of tokens the marketmaker has matched (laid) for this parlay bet.
     * @param odds is the current combined odds as decimal-odds, agreed by both bettor and marketMaker.
     * @param parlayType is the type of the parlay, e.g. regular parlay or agent.
     */
    event ParlayBetAdded(
        bytes32 indexed parlayBetHash,
        bytes32 indexed parlayMarketHash,
        address indexed bettor,
        uint256 betAmount,
        uint256 liquidity,
        uint256 odds,
        ParlayBetType parlayType
    );

    /**
     * @notice Event that fires for each outcome of a parlay bet.
     * @param parlayBetHash identifies this parlay bet.
     * @param eventHash identifies the corresponding event.
     * @param odds is the odds accepted by the bettor on this outcome.
     * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
     * @param outcomeId is the id uniquely defining the outcome type e.g. "homeWin".
     */
    event ParlayBetOutcomeAdded(
        bytes32 indexed parlayBetHash,
        bytes32 indexed eventHash,
        uint256 odds,
        uint32 marketType,
        uint16 outcomeId
    );

    /**
     * @notice Event that fires when the VIP group is updated for a parlay market.
     * @param parlayHash is the hash used to identify the parlay market.
     * @param vipGroup is the new group selected.
     * @param oldGroup is the previous vipGroup value.
     */
    event VIPGroupUpdated(bytes32 indexed parlayHash, uint8 vipGroup, uint8 oldGroup);

    /**
     * @notice Event that fires when liquidity is added to a parlay market.
     * @param parlayHash is the hash used to identify the parlay market.
     * @param added is the amount of liquidity added.
     * @param liquidity is the new total amount of liquidity for this parlay market.
     */
    event ParlayMarketLiquidityAdded(bytes32 indexed parlayHash, uint256 added, uint256 liquidity);

    /**
     * @notice Event that fires when liquidity is removed from a parlay market.
     * @param parlayHash is the hash used to identify the parlay market.
     * @param removed is the amount of liquidity removed.
     * @param liquidity is the new total amount of liquidity for this parlay market.
     */
    event ParlayMarketLiquidityRemoved(bytes32 indexed parlayHash, uint256 removed, uint256 liquidity);

    /**
     * @notice Event that fires when a parlay market is settled.
     * @param parlayHash is the hash used to identify the parlay market.
     * @param owner is the owner of this parlay market (marketmaker).
     * @param amountTotal is the total amount staked in this parlay market, by owner and bettors.
     * @param betsWagered is the number of bets on this parlay market by bettors.
     */
    event ParlayMarketSettled(
        bytes32 indexed parlayHash,
        address indexed owner,
        uint256 amountTotal,
        uint16 betsWagered
    );

    /**
     * @notice Event that fires when a parlay market is settled.
     * @param parlayHash is the hash used to identify the parlay market.
     * @param eventHash identifies the corresponding event.
     * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
     * @param results array of enum that defines if the result is a win, loss or void, when the set is settled.
     *        There is a result for each individual outcome in the set.
     */
    event ParlayMarketOutcomeSetSettled(
        bytes32 indexed parlayHash,
        bytes32 indexed eventHash,
        uint32 marketType,
        ParlayMarketOutcomeResult[] results
    );

    /**
     * @notice Event that fires when a parlay bet is settled.
     * @param parlayBetHash is the hash used to identify the parlay bet.
     * @param result is an enum that defines the result of the bet is a win, loss or void.
     * @param results array of enum that defines if the outcome result is a win, loss or void.
     *        There is a result value for each individual outcome in the bet.
     */
    event ParlayBetSettled(
        bytes32 indexed parlayBetHash,
        ParlayMarketOutcomeResult result,
        ParlayMarketOutcomeResult[] results
    );

    /**
     * @notice Event that fires when the marketmaker is paid, after parlay market settle.
     * @param parlayHash is the hash used to identify the parlay market.
     * @param owner is the owner of this parlay market (marketmaker).
     * @param amountPaid is the amount paid/transfered to the marketmaker.
     * @param amountWon is the profit, from the bettors that lost.
     * @param amountReturned is the amount returned, after the bettors get their profit on the winning outcome.
     * @param amountFeesEarned is the fee amount from bettors earned on this parlay market.
     * @param amountFeesProto is the fee amount paid to the protocol.
     */
    event MarketmakerPayout(
        bytes32 indexed parlayHash,
        address indexed owner,
        uint256 amountPaid,
        uint256 amountWon,
        uint256 amountReturned,
        uint256 amountFeesEarned,
        uint256 amountFeesProto
    );

    /**
     * @notice Event that fires when trying to payout a no-win bet.
     * @param parlayBetHash is the hash used to identify the parlay bet.
     * @param parlayMarketHash is the hash used to identify the parlay market.
     * @param bettor is the wallet address of the bettor.
     * @param amountPaid is the amount paid/transfered to the bettor.
     * @param amountWon is the profit, from the parlay bet.
     * @param amountReturned is the amount returned, that the bettor is not charged fees from.
     * @param amountB2MmFee is the fee amount the bettor paid to marketmaker.
     * @param amountFeesProto is the fee amount paid to the protocol.
     */
    event BettorPayout (
        bytes32 indexed parlayBetHash,
        bytes32 indexed parlayMarketHash,
        address indexed bettor,
        uint256 amountPaid,
        uint256 amountWon,
        uint256 amountReturned,
        uint256 amountB2MmFee,
        uint256 amountFeesProto
    );

    /**
     * @notice Event that fires when trying to payout a no-win bet.
     * @param parlayBetHash is the hash used to identify the parlay bet.
     * @param parlayMarketHash is the hash used to identify the parlay market.
     * @param bettor is the wallet address of the bettor.
     */
    event ParlayBetNoPayout (
        bytes32 indexed parlayBetHash,
        bytes32 indexed parlayMarketHash,
        address indexed bettor
    );

    /**
     * @notice Event that fires when the maximum bet outcome count is set.
     * @param max is the new max value.
     */
    event SetMaxBetOutcomes(uint256 max);

    /**
     * @notice Event that fires when the maximum market outcome count is set.
     * @param max is the new max value.
     */
    event SetMaxMarketOutcomes(uint256 max);

    /**
     * @notice Event that fires when a bettor assigns/removes agent priviliges.
     * @param bettor is the address that assigns parlay betting privileges.
     * @param agent is the address that receives the agent privilege (zero address if none).
     */
    event SetParlayBetAgent(address bettor, address agent);

    /**
     * @notice Error when trying to access a parlay bet that does not exist.
     * @param parlayBetHash is the hash used to identify the parlay bet.
     */
    error InvalidParlayBet(bytes32 parlayBetHash);

    /**
     * @notice Error when trying to access a parlay market that does not exist.
     * @param parlayHash is the hash used to identify the parlay market.
     */
    error InvalidParlayMarket(bytes32 parlayHash);

    /**
     * @notice Error when trying to access a parlay market that has the wrong state.
     * @param parlayHash is the hash used to identify the parlay market.
     */
    error InvalidParlayMarketState(bytes32 parlayHash);

    /**
     * @notice Error when trying to use an invalid number of outcomes.
     * @param count is the maximum allowed number of bet/market outcomes.
     */
    error InvalidParlayOutcomeCount(uint256 count);

    /**
     * @notice Error when trying to access a parlay market outcome set that does not exist or is a duplicate.
     * @param parlayHash is the hash of the parlay market checked.
     * @param eventHash identifies the event for the outcome set.
     * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
     */
    error InvalidParlayMarketOutcomeSet(bytes32 parlayHash, bytes32 eventHash, uint32 marketType);

    /**
     * @notice Error when trying to payout more than the remaining balance.
     * @param parlayHash is the hash used to identify the parlay market.
     * @param requested is the amount of tokens requested paid.
     * @param remaining is the the amount left to pay from, i.e. the full pot with the amounts paid subtracted.
     */
    error InvalidParlayMarketPayout(bytes32 parlayHash, uint256 requested, uint256 remaining);

    /**
     * @notice Error when trying to create/update a parlay market with an invalid liquidity value.
     */
    error InvalidParlayAmountInput();

    /**
     * @notice Error when trying to create/update a parlay market with an invalid outcome value.
     */
    error InvalidMarketOutcomesInput();

    /**
     * @notice Error when trying to create a parlay with invalid market/offset match.
     * @param marketType is a 32 bit unsigned (nonzero) number that identifies the marketType.
     * @param offset is a number value used for some market types like "totals-goals", "spread" etc.
     */
    error InvalidParlayMarketOffsetInput(uint32 marketType, int32 offset);

    /**
     * @notice Error when trying to create/update a parlay market with an invalid odds value.
     */
    error InvalidParlayOddsInput();

    /**
     * @notice Error when trying to add a parlay bet with a duplicate event hash.
     * @param eventHash is the hash of the event checked.
     */
    error InvalidParlayDuplicateEventInput(bytes32 eventHash);

    /**
     * @notice Error for Insufficient token liquidity for an operation.
     * @notice Needed `required` but only `available` available.
     * @param parlayHash is the hash used to identify the parlay market.
     * @param available balance available.
     * @param required requested amount to transfer/withdraw.
     */
    error InsufficientParlayLiquidity(
        bytes32 parlayHash,
        uint256 available,
        uint256 required
    );

    /**
     * @notice Error when trying to add a parlay for a bettor, that did not authorize the sender.
     * @param add is the unauthorized wallet address.
     */
    error NotAgent(address add);

    /**
     * @notice Error when trying to add a parlay bet, that does not match the sender address.
     * @param add is the mismatched wallet address in the data.
     */
    error NotBettor(address add);

    /**
     * @notice Error when trying to add a parlay market without being a MM (no MMbox).
     * @param add is the wallet address that made the violation.
     */
    error NotMarketmaker(address add);

    /**
     * @notice Error when trying to manage a parlay market without ownership.
     * @param parlayHash is the hash of the parlay market.
     * @param add is the wallet/contract address that made the violation.
     */
    error NotMarketOwner(bytes32 parlayHash, address add);

    /**
     * @notice Error when trying to bet on a parlay market without the required VIP credentials.
     * @notice Note: VIP role 255 is never assigned to users, and can be used to temporarily prevent all betting.
     * @param parlayHash is the hash of the parlay market.
     * @param add is the wallet/contract address that made the violation.
     * @param vipGroup is a number between 1 and 255, representing the required vip group for betting.
     */
    error NotVIP(bytes32 parlayHash, address add, uint8 vipGroup);

    function addParlayBet(ParlayBetInput calldata) external;
    function agentParlayBet(ParlayBetInput calldata) external;
    function addParlayMarket(uint256, uint16, uint8, ParlayMarketOutcomeSetData[] calldata) external;
    function addLiquidity(bytes32, uint256) external;
    function removeLiquidity(bytes32, uint256) external;
    function settleParlay(bytes32) external;
    function payoutMarketmaker(bytes32) external;
    function payoutBettor(bytes32) external;
    function setMaxBetOutcomes(uint8) external;
    function setMaxMarketOutcomes(uint8) external;
    function setOdds(bytes32, bytes32, uint32, uint16, uint256) external;
    function setParlayBetAgent(address) external;
    function setVIPGroup(bytes32, uint8) external;

    function getParlayBetData(bytes32) external view returns (ParlayBetData memory);
    function getParlayMarketData(bytes32) external view returns (ParlayMarketData memory);
    function getEventStates(bytes32) external view returns (EventState[] memory);
    function getOutcome(bytes32, bytes32, uint32, uint16) external view returns (ParlayMarketOutcomeData memory);
    function getOwner(bytes32) external view returns (address);
}
