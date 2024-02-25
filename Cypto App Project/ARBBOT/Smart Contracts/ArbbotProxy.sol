// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/* ========== UPGRADABILITY ========== */

// Proxy contract

import "./ArbbotContractV1Salvation_1.sol";

contract ArbbotProxy is AdminRole {
  Arbbot public currentContract;

  constructor(address initialLogic) public {
    currentContract = Arbbot(initialLogic);
  }

  function upgrade(address newLogic) external onlyAdmin {
    currentContract = Arbbot(newLogic);
  }

  fallback() external payable {
    address contractLogic = address(currentContract);
    assembly {
      let ptr := mload(0x40)
      calldatacopy(ptr, 0, calldatasize())
      let result := delegatecall(gas(), contractLogic, ptr, calldatasize(), 0, 0)
      let size := returndatasize()
      returndatacopy(ptr, 0, size)

      switch result
      case 0 { revert(ptr, size) }
      default { return(ptr, size) }
    }
  }


  /* ========== END OF SMART CONTRACT ========== */
} 

/*
try uniswapRouter.swapExactTokensForTokens{gas: TRADE_GAS_LIMIT}(
    amountIn,
    amountOutMin,
    path,
    address(this),
    deadline
) returns (uint[] memory amounts) {
    // Check if the trade was successful
    require(amounts.length > 1 && amounts[1] >= amountOutMin, "Insufficient output");

    // Check if the trade price is consistent with the market price to prevent price manipulation attacks
    uint currentMarketPrice = UniswapV2OracleWrapper.getPrice(info.tokenOut);
    require(amounts[1] >= currentMarketPrice, "Price manipulation detected");

    // Implement a time delay between trade execution and flash loan repayment
    uint tradeExecutionTime = block.timestamp;
    uint repaymentDelay = 5 seconds; // Set the desired time delay

    require(block.timestamp >= tradeExecutionTime + repaymentDelay, "Repayment too early ");

    // Repay the flash loan after the time delay has elapsed
    _repayLoan(amounts[0]);

    // Emit an event indicating that the trade was executed successfully
    emit TradeExecuted(tokenIn, tokenOut, amountIn, amounts[1]);

    // Remove the stop loss and trailing stop loss orders since the trade is complete
    _removeStopLossAndTrailingStopLossOrders(info.tradeId);
}
*/