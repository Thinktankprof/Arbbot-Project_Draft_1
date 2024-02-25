//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/* ========== UPGRADABILITY ========== */

// Proxy contract

import "./Arbbot.sol";


contract ArbbotProxy {
  Arbbot public currentContract;

  constructor(address initialLogic) {
    currentContract = Arbbot(initialLogic);
  }

  function upgrade(address newLogic) external {
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

   receive() external payable {}

  
} 
/* ========== END OF SMART CONTRACT ========== */