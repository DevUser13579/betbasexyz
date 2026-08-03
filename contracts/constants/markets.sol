// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

//  MarketTypes
uint32 constant kMarketType_Undefined = 0;
uint32 constant kMarketType_MoneyLine = 1;
uint32 constant kMarketType_MoneyLine_Home = 2;
uint32 constant kMarketType_MoneyLine_Away = 3;
uint32 constant kMarketType_FulltimeResult = 11;
uint32 constant kMarketType_FulltimeResult_1 = 12;
uint32 constant kMarketType_FulltimeResult_X = 13;
uint32 constant kMarketType_FulltimeResult_2 = 14;
uint32 constant kMarketType_Spread = 21;
uint32 constant kMarketType_Spread_1 = 22;
uint32 constant kMarketType_Spread_2 = 23;
uint32 constant kMarketType_Total = 31;
uint32 constant kMarketType_Total_Over = 32;
uint32 constant kMarketType_Total_Under = 33;
uint32 constant kMarketType_Prediction1 = 51;  // 1 outcome prediction
uint32 constant kMarketType_Prediction2 = 52;  // 2 outcomes prediction
uint32 constant kMarketType_Prediction3 = 53;
uint32 constant kMarketType_Prediction4 = 54;
uint32 constant kMarketType_Prediction5 = 55;
uint32 constant kMarketType_MainHandlerMax = 100;

//  Outcomes
uint16 constant kOutcome_Undefined = 0;
uint16 constant kOutcome_HomeWin = 1;
uint16 constant kOutcome_AwayWin = 2;
uint16 constant kOutcome_Draw = 3;
uint16 constant kOutcome_Over = 11;
uint16 constant kOutcome_Under = 12;
uint16 constant kOutcome_Prediction1 = 51;  // Same numeric values af market types, for easier compatibility checks
uint16 constant kOutcome_Prediction2 = 52;
uint16 constant kOutcome_Prediction3 = 53;
uint16 constant kOutcome_Prediction4 = 54;
uint16 constant kOutcome_Prediction5 = 55;
