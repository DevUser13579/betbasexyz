// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Types are all possible, Undefined means not existing bet.
enum BetType { Undefined, Market, Agent } // Enum

/**
 * @param marketHash is the hash that uniquely identifies the market/parlay.
 * @param bettor is the wallet address of the bettor.
 * @param outcomeId is a number from 0 - 65535 to define the outcome, as seen from the bettor.
 * @param betType is the type of the bet, e.g. regular market or agent.
 * @param betAmount is the amount of tokens the bettor has bet (backed) on the market.
 * @param odds is the odds accepted for this bet, in decimal-odds format, with 3 decimals.
 */
struct BetData {
    bytes32 marketHash;
    address bettor;
    uint16 outcomeId;
    BetType betType;
    uint256 betAmount;
    uint256 odds;
}

interface IBetHandler {
    /**
     * @notice Event that fires when the token is set.
     * @param add is the new address.
     */
    event SetToken(address add);

    /**
     * @notice Event that fires when the MarketHandler is set.
     * @param add is the new address.
     */
    event SetMarketHandler(address add);

    /**
     * @notice Event that fires when the BetBox is set.
     * @param add is the new address.
     */
    event SetBetBox(address add);

    /**
     * @notice Event that fires when a bettor/owner assigns/removes agent priviliges.
     * @param owner is the address that assigns betting privileges.
     * @param agent is the address that receives the agent privilege (zero address if none).
     */
    event BetAgentSet(address owner, address agent);

    /**
     * @notice Event that fires when a new bet is made.
     * @param betHash is the hash used to identify the bet.
     * @param marketHash is the hash used to identify the market.
     * @param bettor is the wallet address of the bettor.
     * @param outcomeId is the id uniquely defining an outcome type e.g. kOutcome_HomeWin.
     * @param betType is the type of the bet, e.g. regular market og parlay.
     * @param betAmount is the amount of tokens the bettor has bet (backed) on the market.
     * @param odds is the odds accepted for this bet, in decimal-odds format, with 3 decimals.
     */
    event BetAdded (
        bytes32 indexed betHash,
        bytes32 indexed marketHash,
        address indexed bettor,
        uint16 outcomeId,
        BetType betType,
        uint256 betAmount,
        uint256 odds
    );

    /**
     * @notice Event that fires when trying to payout a no-win bet.
     * @param betHash is the hash used to identify the bet.
     * @param marketHash is the hash used to identify the market.
     * @param bettor is the wallet address of the bettor.
     * @param outcomeId is the id uniquely defining an outcome type e.g. kOutcome_HomeWin.
     */
    event BetNoPayout (
        bytes32 indexed betHash,
        bytes32 indexed marketHash,
        address indexed bettor,
        uint16 outcomeId
    );

    /**
     * @notice Event that fires when the marketmaker is paid, after market settle.
     * @param betHash is the hash used to identify the bet.
     * @param marketHash is the hash used to identify the market.
     * @param bettor is the owner of this bet.
     * @param amountPaid is the amount paid/transfered to the bettor.
     * @param amountWon is the profit for the bettor.
     * @param amountReturned is the amount returned without a fee (betAmount for win, Void amount etc.).
     * @param amountFeesToMm is the fee amount paid to marketmaker.
     * @param amountFeesProto is the fee amount paid to the protokol.
     */
    event BettorPayout(
        bytes32 indexed betHash,
        bytes32 indexed marketHash,
        address indexed bettor,
        uint256 amountPaid,
        uint256 amountWon,
        uint256 amountReturned,
        uint256 amountFeesToMm,
        uint256 amountFeesProto
    );

    /**
     * @notice Error when trying to access a bet that does not exist or create a duplicate.
     * @param betHash is the hash used to identify the bet.
     */
    error InvalidBet(bytes32 betHash);

    /**
     * @notice Error when trying to bet too large an amount.
     * @param amount is the amount of the attempted the bet.
     */
    error InvalidBetAmount(uint256 amount);

    /**
     * @notice Error when trying to bet, without agent priviliges.
     * @param owner is the address that would own the bet.
     * @param agent is the address that was denied to make the bet.
     */
    error BetNotAllowed(address owner, address agent);

    /**
     * @notice Error when trying to bet with odds that does not match the market.
     * @param marketHash is the hash used to identify the market.
     * @param outcomeId is the id uniquely defining an outcome type e.g. kOutcome_HomeWin.
     * @param requested is the odds requested.
     * @param expected is the odds of the market.
     */
    error InvalidOdds(bytes32 marketHash, uint16 outcomeId, uint256 requested, uint256 expected);

    /**
     * @notice Error when trying to payout too many bets at once.
     * @param limit is the limit of bets.
     */
    error LimitExceeded(uint8 limit);

    function setBetAgent(address) external;
    function addBet(bytes32, uint256, uint256, uint16) external;
    function agentBet(bytes32, address, uint256, uint256, uint16) external;
    function payoutBet(bytes32) external;
    function payoutBets(bytes32[] calldata) external;
    // Auto getters from public vars
    function token() external view returns(address);
    function tokenDecimals() external view returns(uint8);
}
