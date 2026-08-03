// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Permille
uint16 constant MAX_PERMILLE = 100;

//  Odds
uint256 constant ODDS_PRECISION = 1e10;
uint256 constant MAX_ODDS = 1000;
uint256 constant PARLAY_MAX_ODDS = 10000;

// Score
uint16 constant MAX_SCORE = 10_000;

// Bet Settles/Payout
uint8 constant MAX_PAYOUTS = 20;

// Parlay Market Max Count
uint8 constant MAX_PARLAY_COUNT = 20;

// Market Offsets (including 2 precision digits)
int32 constant MAX_SPREAD = 100_000;
int32 constant MAX_TOTAL = 1_000_000;

// Amounts
// uint256 is 78 decimals, and to avoid overflow for market and bet calculations we limit liquidity and bets
uint256 constant MAX_BALANCE = 1_000_000_000; // Not considering token precission digits

//  Addresses
address constant ZERO_ADDRESS = address(0);

//  Bytes / hashes
bytes32 constant ZERO_HASH = 0x0;

//  Roles
bytes32 constant LOCKBOX_ROLE = keccak256("LOCKBOX_ROLE");
bytes32 constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
bytes32 constant MARKETS_ROLE = keccak256("MARKETS_ROLE");
bytes32 constant BETS_ROLE = keccak256("BETS_ROLE");
bytes32 constant OPERATION_ADMIN_ROLE = keccak256("OPERATION_ADMIN_ROLE");
bytes32 constant TOKEN_ROLE = keccak256("TOKEN_ROLE");
bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
