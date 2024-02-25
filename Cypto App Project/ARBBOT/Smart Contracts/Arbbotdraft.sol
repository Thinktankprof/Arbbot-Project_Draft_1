// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
Arbbot - Flashloan arbitrage trading bot

This bot performs arbitrage between decentralized exchanges by utilizing flashloans.
Trades across exchange pairs to capitalize on price discrepancies for profit.

Designed for gas optimization, security, reliability and upgradability.

By Anthropic's Claude AI Assistant
*/

/**
 * @title Interfaces 
 * @dev Interface definitions for external contracts
*/
// Interfaces
interface IUniswapV2Router02 {
  function swapExactTokensForTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  ) external returns (uint[] memory amounts);
  
}

interface IAaveLendingPool {
  function flashLoan(
    address receiver, 
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata modes,
    address onBehalfOf,
    bytes calldata params,
    uint16 referralCode    
  ) external;
}

// Utility libraries
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/gas/GasEstimator.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@aave/protocol/contracts/interfaces/ILendingPool.sol";
import "@openzeppelin/contracts/utils/Timers.sol";


// Proxy contract for upgradability
import "./ArbbotProxy.sol";

/**
 * @title Arbbot
 * @dev Main Arbbot contract for flashloan arbitrage
*/

contract Arbbot is ReentrancyGuard {

  using SafeMath for uint;

  /* ========== STATE VARIABLES ========== */
  
  address public owner; // Owner address
  
  bool public paused; // Pause trading

  uint public nextBatchId; // Flags and variables

  bool private locked;

  GasEstimator internal gasEstimator;

  mapping(address => bool) public userRoles; 

  mapping(bytes32 => uint) public loanRepaidBlock;

  // Constants

  // Role definitions
  bytes32 public constant OWNER_ROLE = keccak256("OWNER");
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER");
  bytes32 public constant TRADER_ROLE = keccak256("TRADER");

  uint private constant TRADE_GAS_LIMIT = 250000;  
    
  address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

  // Parameters
  uint public minProfitMargin = 10;
  uint public slippageTolerance = 20;
  uint public stopLossRatio = 30;
  uint public trailingStopLossRatio = 10;
  uint public flashLoanFee;
  using Timers for Timers.Timer;
  Timers.Timer public timer;
   
  // Dedicated profit account
  address public profitAccount = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

  
  // User roles mapping
  mapping(address => bytes32) public userRoles;
  mapping(address => bool) public userRoles;


  // Interfaces
  AggregatorV3Interface internal priceFeed;
  IUniswapV2Router02 internal uniswapRouter;
  ILendingPool internal lendingPool;

   
  // Structs
  struct ArbInfo {
    address tokenIn;
    address tokenOut;
  }

  struct ArbBatch {
    bytes32[] batchOpportunities;
    uint256 batchId;
  }

  struct TokenPair {
    address[3] tokenIn;
    address[3] tokenOut;
    bool locked;
  }

  struct TokenInfo {
    string name; // E.g. Wrapped Ether
    address token; // Token contract address
  }


 // Structs
  struct ArbInfo {
    address tokenIn;
    address tokenOut;
  }

  struct ArbBatch {
    bytes32[] batchOpportunities;
    uint256 batchId;
  }
   
  struct TokenPair {
    address[3] tokenIn;
    address[3] tokenOut;
    bool locked;
  }

  TokenPair tokenPairs = TokenPair({
    tokenIn: [
      // Token 1 address
      // Token 2 address
      // Token 3 address
    ],
    tokenOut: [
      // Token 1 address
      // Token 2 address
      // Token 3 address
    ]
  });

  // Mapping of token symbols to TokenInfo
  mapping(string => TokenInfo) public tokens;

  // Mapping to track arbitrage opportunities for each pair
  mapping(bytes32 => bool) public arbitrageOpportunitySet;

  // Mappings
  mapping(bytes32 => ArbInfo) public arbOpportunities;
  mapping(uint256 => ArbBatch) public pendingBatches;



  /* ========== EXTERNAL FUNCTIONS ========== */


  struct ArbInfo {
    address tokenIn;
    address tokenOut;
  }

  struct ArbBatch {
    bytes32[] batchOpportunities;
    uint256 batchId;
  }


  // Updated TokenPair Struct
  struct TokenPair {
    address[3] tokenIn;
    address[3] tokenOut;
    bool locked;
  }

  // Updated State Variables
  TokenPair public tokenPairs;  // Assuming you want a global tokenPairs variable

  // Create an arbitrage batch with the asset pair addresses.
  smartContract.createArbBatch(opportunityIds, tokenInAddresses, tokenOutAddresses);

  // Existing Mappings
  mapping(bytes32 => bool) public arbitrageOpportunitySet;
  mapping(bytes32 => ArbInfo) public arbOpportunities;
  mapping(uint256 => ArbBatch) public pendingBatches;

  // New State Variables
  mapping(address => TokenPair) public userTradePairAddresses;
  mapping(address => bool) public traders;


  // Interface instances 
	
  IUniswapV2Router public uniswap; // Uniswap interface
  IAaveLendingPool public aave; // Aave pool interface
  
  // Token mappings
  mapping(address => TokenInfo) public tokens;

  // Arbitrage opportunity mapping
  mapping(bytes32 => ArbInfo) public arbOpportunities;

  // Role definitions
  bytes32 public constant OWNER_ROLE = keccak256("OWNER");
  bytes32 public constant TRADER_ROLE = keccak256("TRADER");

  // User roles mapping
  mapping(address => bytes32) public userRoles;
  mapping(address => bool) public userRoles;


 

  /* ========== EVENTS ========== */

  event ArbStarted(
    uint256 id, 
    address indexed tokenIn,
    address indexed tokenOut
  );
  
  event ArbCompleted(
    uint256 id,
    address indexed tokenIn,
    address indexed tokenOut,
    uint256 profit  
  );

  // Add these event declarations to your contract
  event ArbitragePairAdded(address tokenIn, address tokenOut);
  event ArbExecuted(bytes32 id, address tokenIn, address tokenOut, uint profit);
  event ArbFailed(bytes32 id, string reason);
  event TradeExecuted(address tokenIn, address tokenOut, uint amountIn, uint amountOut);

  event ProfitRealized(bytes32 opportunityId, uint256 profit);

  // Listen for the ProfitRealized event.
  // Function to handle the 'ProfitRealized' event
  function profitRealizedHandler(bytes32 opportunityId, uint256 profit) internal {
    // Update the front end UI to show the current profit for the opportunity ID
    updateFrontEndUI(opportunityId, profit);
  }

  /*smartContract.on("ProfitRealized", (event) => {
    // Get the opportunity ID and profit from the event data.
    bytes32 opportunityId = event.args.opportunityId;
    uint profit = event.args.profit;

    // Update the front end UI to show the current profit for the opportunity ID.
    updateFrontEndUI(opportunityId, profit);
  });*/
  
  /* ========== MODIFIERS ========== */

  modifier onlyOwner() {
    require(msg.sender == owner, "Not owner");
    _;
  }  

  modifier nonReentrant() {
    require(!locked, "No reentrancy");
    locked = true;
    _;
    locked = false;
  }

  modifier whenNotPaused() {
    require(!paused, "Contract is paused");
    _;
  }
  
  modifier onlyUserRole(string memory role) {
    require(userRoles[msg.sender], role);
    _;
  }


  // Modifier for "TRADER" role
  modifier onlyUserRole(string memory role) {
    require(userRoles[msg.sender] == keccak256(bytes(role)), "Access denied");
    _;
  }

  function setUserRole(address userAddress, string memory role) external onlyOwner {
    userRoles[userAddress] = role;
  }

  function pause() external onlyOwner {
   paused = true;
  }

  function unpause() external onlyOwner  {
   paused = false;
  } 

  function hasRole(bytes32 role, address user) view returns (bool) {
   return userRoles[user] == role; 
  }

  function addRole(bytes32 role, address user) external onlyRole(OWNER_ROLE) {
   userRoles[user] = role;
  }

  function removeRole(bytes32 role, address user) external onlyRole(OWNER_ROLE) {
   delete userRoles[user];
  }

  /* ========== CONSTRUCTOR ========== */


  // Constructor
  constructor(address _priceFeed, address _uniswapRouter, address _lendingPool, address _profitAccount) {
    owner = msg.sender;
    priceFeed = AggregatorV3Interface(_priceFeed);
    uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    lendingPool = ILendingPool(_lendingPool);
    profitAccount = _profitAccount;
    // Grant deployer the default admin role
    userRoles[msg.sender] = OWNER_ROLE; 
    // Initialize the gas estimator.
    gasEstimator = new GasEstimator();
  }

  /* ========== EXTERNAL FUNCTIONS ========== */

  /**
  * @notice Initiate a new arbitrage opportunity
  * @param tokenIn: Input token symbol
  * @param tokenOut: Output token symbol
  * @param tokenIn: Input token address
  * @param tokenOut: Output token address
  * @dev Starts an arbitrage process by calling out to startArbitrage 
  */
   
  bool locked = false;

  function externalCall() external {
    require(!locked, "No reentrancy");
    locked = true;
    // Interact with external contract
    locked = false;
  }

  // External

  function startArbitrage(address tokenIn, address tokenOut) external nonReentrant onlyRole(OWNER_ROLE || TRADER) whenNotPaused {
    // Add and start arbitrage for the specified pairs
    TokenPair[] memory pairs = new TokenPair[](3);
    pairs[0] = TokenPair({
    tokenIn: [tokenIn1, address(0), address(0)],
    tokenOut: [tokenOut1, address(0), address(0)],
    locked: false
    });
    pairs[1] = TokenPair({
    tokenIn: [tokenIn2, address(0), address(0)],
    tokenOut: [tokenOut2, address(0), address(0)],
    locked: false});
    pairs[2] = TokenPair({
    tokenIn: [tokenIn2, address(0), address(0)],
    tokenOut: [tokenOut2, address(0), address(0)],
    locked: false});

    // Add and start arbitrage for the specified pairs
    addAndStartArbitragePairs(pairs);
  }
    

  function addAndStartArbitragePairs(TokenPair[] memory pairs) external nonReentrant onlyRole(OWNER_ROLE || TRADER) whenNotPaused {
    bytes32[] memory opportunityIds = new bytes32[](pairs.length);

    for (uint i = 0; i < pairs.length; i++) {
      bytes32 id = keccak256(abi.encodePacked(pairs[i].tokenIn[0], pairs[i].tokenOut[0]));
      if (!arbitrageOpportunitySet[id]) {
        arbOpportunities[id] = ArbInfo(pairs[i].tokenIn[0], pairs[i].tokenOut[0]);
        arbitrageOpportunitySet[id] = true;
        emit ArbitragePairAdded(pairs[i].tokenIn[0], pairs[i].tokenOut[0]);
      }
    }

    // Execute all opportunities in the batch
    _executeBatchOpportunities(opportunityIds);

  }
  
  function createArbBatch(bytes32[] calldata opportunityIds, 
    address[3] calldata tokenInAddresses,
    address[3] calldata tokenOutAddresses
    ) external nonReentrant onlyRole(OWNER_ROLE || TRADER) 
    whenNotPaused {
    uint256 batchId = nextBatchId++;
    pendingBatches[batchId].batchOpportunities = opportunityIds;
    pendingBatches[batchId].tokenPairAddress = tokenInAddresses;
    pendingBatches[batchId].tokenOutAddress = tokenOutAddresses;
  }

  

  function setUserTradePairAddresses(address[3] memory tokenInAddresses, 
    address[3] memory tokenOutAddresses) 
    external onlyUserRole("TRADER") {
    // Store the asset pair addresses for the user's app stance.
    userTradePairAddresses[msg.sender] = TokenPair({
    tokenIn: tokenInAddresses,
    tokenOut: tokenOutAddresses,
    locked: true
    });
  }

  // Get the asset pair addresses for the user's app stance.
  address[3] memory tokenInAddresses = userTradePairAddresses[msg.sender].tokenIn;
  address[3] memory tokenOutAddresses = userTradePairAddresses[msg.sender].tokenOut;

  // Create an arbitrage batch with the asset pair addresses.
  smartContract.createArbBatch(opportunityIds, tokenInAddresses, tokenOutAddresses);

  function unlockTradePairAddresses(address userAddress) external onlyOwner {
    userTradePairAddresses[userAddress].locked = false;
  }


  function addTrader(address trader) external onlyOwner {
    traders[trader] = true; 
  }

  function removeTrader(address trader) external onlyOwner {
    traders[trader] = false;
  }

  function _executeBatchOpportunities(bytes32[] memory opportunityIds) internal {
    // Create a new batch with the opportunity IDs
    createArbBatch(opportunityIds);

    for (uint i = 0; i < opportunityIds.length; i++) {
        _executeSingleArb(opportunityIds[i]);
    }
  }

  //Define Subscription Categories
  //Use enumerations to define the different subscription categories

  enum SubscriptionPackage { Silver, Gold, Diamond }

  // Payout rates for each package
  mapping(SubscriptionPackage => uint256) public payoutRates;

  // Additional mapping for Diamond package options
  mapping(address => uint256) public diamondPayoutOptions;


  //Define User Struct
  //User struct to store user-related data, including their subscription category and payout address

  struct User {
    SubscriptionCategory subscription;
    address payoutAddress;
    uint256 subscriptionExpiry; // Timestamp when the subscription expires
  }

  //User Registration
  //Implement a function that allows users to register, specifying their subscription category, payout address, and subscription duration. The contract owner (you) can assign Diamond status to certain users.

  function registerUser(
    SubscriptionPackage subscription,
    address payoutAddress,
    uint256 subscriptionDuration,
    uint256 diamondPayoutRate // Only for Diamond users
    ) external {
    require(subscriptionDuration > 0, "Subscription duration must be greater than 0");

    // Check if the user is eligible for Diamond status
    if (msg.sender == owner) {
    require(subscription == SubscriptionPackage.Diamond, "Only the owner can assign Diamond status");
    }

    // Calculate the subscription expiry timestamp
    uint256 expiryTimestamp = block.timestamp + subscriptionDuration;

    // Create a new user and store their information
    users[msg.sender] = User(subscription, payoutAddress, expiryTimestamp);

    // Set the payout rate for Diamond users (if applicable)
    if (subscription == SubscriptionPackage.Diamond) {
    diamondPayoutOptions[msg.sender] = diamondPayoutRate;
    }
  }

  //Profit Sharing and Payout
  //Calculate the user's share of the accumulated profit and sends it to their payout address.This function can be called periodically based on the payout interval (e.g., weekly or monthly). 

  function payoutProfit(address userAddress) external onlyOwner {
    User storage user = users[userAddress];
    require(user.subscription != SubscriptionPackage(0), "User not registered");

    // Calculate the user's share of the profit based on the subscription package and payout rate
    uint256 share;
    if (user.subscription == SubscriptionPackage.Silver) {
    // Silver package: subscription amount + 10%
    share = (subscriptionAmount + subscriptionAmount * 10 / 100) / subscriptionDuration;
    } else if (user.subscription == SubscriptionPackage.Gold) {
    // Gold package: subscription amount + 25%
    share = (subscriptionAmount + subscriptionAmount * 25 / 100) / subscriptionDuration;
    } else if (user.subscription == SubscriptionPackage.Diamond) {
    // Diamond package: Use the selected payout rate (0.5% to 5% of daily profit)
    uint256 payoutRate = diamondPayoutOptions[userAddress];
    // Calculate the daily profit and distribute the payout
    share = (calculateDailyProfit() * payoutRate) / 100;
    }

    // Check if the current time is within the payout period
    require(block.timestamp < user.subscriptionExpiry, "Subscription has expired");

    // Send the user's share of profit to their payout address
    // Deduct the profit from the accumulated pool
    // Implement the payout logic based on your requirements
  }



  //Subscription Renewal
  //Allow users to renew their subscriptions when they expire.

  function renewSubscription(uint256 subscriptionDuration) external {
    User storage user = users[msg.sender];
    require(user.subscription != SubscriptionCategory(0), "User not registered");
    require(block.timestamp >= user.subscriptionExpiry, "Subscription has not expired yet");

    // Calculate the new subscription expiry timestamp
    uint256 expiryTimestamp = block.timestamp + subscriptionDuration;

    // Update the user's subscription expiry timestamp
    user.subscriptionExpiry = expiryTimestamp;
  }


  //Sending Remaining Profits to App Owner
  //Implement a function that allows the app owner to withdraw the remaining profits when a user's subscription expires

  function withdrawRemainingProfits() external onlyOwner {
    require(block.timestamp >= user.subscriptionExpiry, "User's subscription has not expired yet");
    require(accumulatedProfits > 0, "No profits to withdraw");
  
    // Send the accumulated profits to the app owner's dedicated wallet address
    payable(owner).transfer(accumulatedProfits);
  
    // Reset the accumulated profits to zero
    accumulatedProfits = 0;
  }



  function addTrader(address trader) external onlyOwner {
    traders[trader] = true; 
  }
  
  function removeTrader(address trader) external onlyOwner {
    traders[trader] = false;
  }

  function setSlippageTolerance(uint tolerance) external onlyOwner {
    slippageTolerance = tolerance;
  }



  /* ========== INTERNAL FUNCTIONS ========== */

  /**
  * @notice Execute arbitrage trade
  * @param id: Unique identifier 
  * @param tokenIn: Input token
  * @param tokenOut: Output token
  */

  // Internal

  function _executeSingleArb(bytes32 id) internal {

    ArbInfo storage info = arbOpportunities[id];

    if (!_checkProfitability(info)) {
      emit ArbFailed(id, "Not profitable");
      return; 
    }

    // Execute trade
    uint profit = _executeTrade(info);
    
    emit ArbExecuted(id, info.tokenIn, info.tokenOut, profit); 

  }

  function _executeTrade(ArbInfo memory info) internal returns (uint) {

    // Take loan

    // Flag to track whether the flash loan has been received
    bool flashLoanReceived = false;

    function _takeLoan(uint amount) internal {
      // Get the token to borrow
      address token = arbInfo.tokenIn;

      // Check if the loan amount is valid
      require(amount > 0, "Invalid loan amount");

      // Check if the flash loan has already been received to prevent reentrancy attacks
      require(!flashLoanReceived, "Flash loan already received");

      // Request a flash loan from the Aave lending pool
      bool flashLoanSuccess = aaveLendingPool.flashLoan(
        address(this), // The address to receive the loan funds
        token, // The token to borrow
        amount, // The amount to borrow
        0, // Flash loan mode (no special mode)
        this, // Callback function to execute after the flash loan is received
        0 // Referral code (not used in this case)
      );

      // Check if the flash loan was successful
      if (!flashLoanSuccess) {
        revert("Flash loan failed");
      }

      // Mark the flash loan as received to prevent reentrancy attacks
      flashLoanReceived = true;

      // Validate that the loan amount was received correctly
      require(amounts[0] == amount, "Invalid loan amount received");
      emit LoanTaken(amount); // Emit an event to indicate that the loan was taken

      // Check for dust attacks
      require(amounts[0] > 0, "Loan amount too small to repay");

      // Check for sybil attacks
      uint borrowerBalance = token.balanceOf(address(this));
      require(borrowerBalance >= amounts[0], "Insufficient funds to repay loan");

      // Proceed with the trade using the borrowed tokens
      _makeTrade(arbInfo);

      // Repay the flash loan along with the accrued fee
      _repayLoan(amounts[0]);

      // Reset the flash loan received flag after the loan is repaid
      flashLoanReceived = false;
    }


    function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator, 
    bytes calldata params
    ) external returns (bool) {

     // Validate callback is expected
     require(msg.sender == address(aaveLendingPool), "Invalid callback");

     ArbInfo memory info = abi.decode(params, (ArbInfo));

     // Make arbitrage trade
     _makeTrade(info);
  
  
     // Repay loan
     mapping(bytes32 => uint) public loanRepaidBlock;
     _repayLoan(amounts[0]);
 
     return true;
 
    }

    // Make trade

    function _makeTrade(ArbInfo memory info) internal {
      // Get the stop loss and trailing stop loss ratios
      uint stopLossRatio = info.stopLossRatio;
      uint trailingStopLossRatio = info.trailingStopLossRatio;

      // Calculate the stop loss price
      uint stopLossPrice = info.output - (info.output * stopLossRatio / 100);

      // Calculate the trailing stop loss price
     uint trailingStopLossPrice = stopLossPrice;

      // Place the stop loss and trailing stop loss orders
      _placeStopLossOrder(info, stopLossPrice);
      _placeTrailingStopLossOrder(info, trailingStopLossPrice);

      // Define the token paths for the arbitrage trade and profit conversion
      ddress[] memory tradePath = new address[](2);
      tradePath[0] = info.tokenIn;
      tradePath[1] = info.output;

      // Calculate the input amount based on the trade parameters
      uint amountIn = _getInputAmount(info);

      // Calculate the minimum output amount based on the input amount and the current market price
      uint amountOutMin = _getMinimumOutputAmount(amountIn);
   

      // Approve the token transfer to the Uniswap router
      token.approve(address(uniswapRouter), amountIn);
    
      // Execute the swap using the Uniswap router
      try uniswapRouter.swapExactTokensForTokens{gas: TRADE_GAS_LIMIT}(
      amountIn,
      amountOutMin,
      path,
      address(this),
      deadline) returns (uint[] memory amounts) {
        // Check if the trade was successful
        require(amounts.length > 1 && amounts[1] >= amountOutMin, "Insufficient output");

        // Check if the trade price is consistent with the market price to prevent price manipulation attacks
        uint currentMarketPrice = UniswapV2OracleWrapper.getPrice(info.tokenOut);
        require(amounts[1] >= currentMarketPrice, "Price manipulation detected");  

        // Implement a mechanism to detect frontrunning attacks, such as a time delay or a reputation system

        // Repay the flash loan after the trade is executed
        _repayLoan(amounts[0]);

        // Emit an event indicating that the trade was executed successfully
        emit TradeExecuted(tokenIn, tokenOut, amountIn, amounts[1]);

        // Remove the stop loss and trailing stop loss orders since the trade is complete
        _removeStopLossAndTrailingStopLossOrders(info.tradeId);
      } catch { 
        // If the trade fails with a low gas limit, try again with a higher gas limit
        try uniswapRouter.swapExactTokensForTokens{gas: TRADE_GAS_LIMIT + 50000} 
        (amountIn, amountOutMin, path,address(this), deadline) 
        returns (uint[] memory amounts) {
          // Check if the trade was successful with the higher gas limit
          require(amounts.length > 1 && amounts[1] >= amountOutMin, "Insufficient output");

          // Check if the trade price is consistent with the market price to prevent price manipulation attacks
          uint currentMarketPrice = UniswapV2OracleWrapper.getPrice(info.tokenOut);
          require(amounts[1] >= currentMarketPrice, "Price manipulation detected");

          // Implement a mechanism to detect frontrunning attacks, such as a time delay or a reputation system

          // Repay the flash loan after the trade is executed
          _repayLoan(amounts[0]);

          // Emit an event indicating that the trade was executed successfully
          emit TradeExecuted(tokenIn, tokenOut, amountIn, amounts[1]);

          // Remove the stop loss and trailing stop loss orders since the trade is complete
          _removeStopLossAndTrailingStopLossOrders(info.tradeId);
        } catch {
          // If the trade fails even with a higher gas limit, revert the transaction
          revert("Trade failed");
        }

        // While the trade is active, monitor the market price and update the stop loss and trailing stop loss orders if necessary
        while (tradeActive) {
          uint currentPrice = UniswapV2OracleWrapper.getPrice(info.tokenOut);

          // Update the stop loss and trailing stop loss orders if the market price has changed significantly
          if (currentPrice != lastPrice) {
            _updateStopLossAndTrailingStopLossOrders(currentPrice);
          }

          // Check if the stop loss price has been triggered
          if (currentPrice <= stopLossPrice) {
            // Cancel the trade
            _cancelTrade();

            // Break out of the loop
            break;
          }

          // Wait for some time before polling the current market price

          uint pollingInterval = 10; // seconds

          // Use a timer library to wait for the pollingInterval number of seconds to pass.
          Timer timer;
          timer.start(pollingInterval);
          timer.wait();

          // Validate trade output
          require(output >= amountOutMin, "Insufficient output");

          _removeStopLossAndTrailingStopLossOrders(uint tradeId);  
        }
      }
    }

  }
  // Update stop loss and trailing stop loss orders

  function _updateStopLossAndTrailingStopLossOrders(currentPrice) internal {

    // Get the current market price.
    uint currentMarketPrice = UniswapV2OracleWrapper.getPrice(info.tokenOut);

    // Update the stop loss price.
    if (stopLossOrders[info.tradeId].price != currentMarketPrice) {
      stopLossOrders[info.tradeId].price = currentMarketPrice;
    }

    // Update the trailing stop loss price.
    if (trailingStopLossOrders[info.tradeId].price != currentMarketPrice * trailingStopLossRatio / 100) {
      trailingStopLossOrders[info.tradeId].price = currentMarketPrice * trailingStopLossRatio / 100;
    }
  }


  // Place stop loss order

  function _placeStopLossOrder(ArbInfo memory info, uint stopLossPrice) internal {

    // Create a stop loss order object.
    StopLossOrder memory stopLossOrder;
    stopLossOrder.token = info.tokenOut;
    stopLossOrder.price = stopLossPrice;
    stopLossOrder.amount = info.output;

    / Place the stop loss order.
    UniswapV2Exchange(info.dexAddress).placeStopLossOrder(stopLossOrder);

    // Save the stop loss order for later use.
    stopLossOrders[info.tradeId] = stopLossOrder;
  }


  // Place trailing stop loss order

  function _placeTrailingStopLossOrder(ArbInfo memory info, uint trailingStopLossPrice) internal {

    // Create a trailing stop loss order object.

    TrailingStopLossOrder memory trailingStopLossOrder;
    trailingStopLossOrder.token = info.tokenOut;
    trailingStopLossOrder.price = trailingStopLossPrice;
    trailingStopLossOrder.amount = info.output;

    // Place the trailing stop loss order.
    UniswapV2Exchange(info.dexAddress).placeTrailingStopLossOrder(trailingStopLossOrder);

    // Save the trailing stop loss order for later use.
    trailingStopLossOrders[info.tradeId] = trailingStopLossOrder;
  }


  // Remove or cancel stop loss order

  function _removeStopLossOrder(uint tradeId) internal {

    // Get the stop loss order.
    StopLossOrder memory stopLossOrder = stopLossOrders[tradeId];

    // Cancel the stop loss order.
    // UniswapV2Exchange(info.dexAddress).cancelStopLossOrder(stopLossOrder);

    // Remove the stop loss order from the mapping.
    delete stopLossOrders[tradeId];
  }


  // Remove or cancel trailing stop loss order

  function _removeTrailingStopLossOrder(uint tradeId) internal {

    // Get the trailing stop loss order.
    TrailingStopLossOrder memory trailingStopLossOrder = trailingStopLossOrders[tradeId];

    // Cancel the trailing stop loss order.
    UniswapV2Exchange(info.dexAddress).cancelTrailingStopLossOrder(trailingStopLossOrder);

    // Remove the trailing stop loss order from the mapping.
    delete trailingStopLossOrders[tradeId];
  }


  // Remove or cancel stop loss and trailing stop loss orders

  function _removeStopLossAndTrailingStopLossOrders(uint tradeId) internal {

    // Remove the stop loss order.
    _removeStopLossOrder(tradeId);

    // Remove the trailing stop loss order.
    _removeTrailingStopLossOrder(tradeId);
  }


  // Update stop loss and trailing stop loss orders

  function _updateStopLossAndTrailingStopLossOrders() internal {

    // Get the current market price.
    uint currentMarketPrice = UniswapV2OracleWrapper.getPrice(info.tokenOut);

    // Update the stop loss price.
    if (stopLossOrders[info.tradeId].price != currentMarketPrice) {
      stopLossOrders[info.tradeId].price = currentMarketPrice;
    }

    // Update the trailing stop loss price.
    if (trailingStopLossOrders[info.tradeId].price != currentMarketPrice * trailingStopLossRatio / 100) {
      trailingStopLossOrders[info.tradeId].price = currentMarketPrice * trailingStopLossRatio / 100;
    }
  }



  function _cancelTrade(ArbInfo memory info) internal {

    // Cancel all open orders for the trade
    _cancelAllOpenOrdersForTrade(uint tradeId);

    // Update the trade status to canceled
    info.tradeStatus = TradeStatus.Canceled;

  }


  // Cancel all open orders for the trade
  function _cancelAllOpenOrdersForTrade(uint tradeId) internal {

    // Get the addresses of the open orders for the trade
    address[] memory openOrderAddresses = info.openOrderAddresses;

    // Cancel all open orders for the trade
    for (uint i = 0; i < openOrderAddresses.length; i++) {
      // Call the appropriate function on the DEX to cancel the open order
      info.dexAddress.cancelOrder(openOrderAddresses[i]);
    }

  }
  
  // Repay loan

  function _repayLoan(uint amount) internal {

    // Get token to borrow
    address token = arbInfo.tokenIn;

    // If the FLASH_LOAN_FEE is not cached, get it from Aave.
    if (flashLoanFee == 0) {
      flashLoanFee = IAaveLendingPool(aave).FLASHLOAN_PREMIUM_TOTAL();
    }

    // Calculate repayment amount
    uint repayAmount = amount + premium;

    // Check for dust attack
    require(repayAmount > 0, "Loan amount too small to repay");

    // Check for sybil attack
    uint borrowerBalance = token.balanceOf(address(this));
    require(borrowerBalance >= repayAmount, "Insufficient funds to repay loan");

    // Approve tokens if needed
    token.approve(address(lendingPool), repayAmount);

    // Calculate the fee using the cached FLASH_LOAN_FEE.
    uint fee = (amount * flashLoanFee) / 10000;

    // Emit the loan fee event.
    emit LoanFeeEmitted(amount, fee);

    // Transfer the repayment amount and fee to the lending pool
    transferToken(token, aaveLendingPool, repayAmount);

    // Repay flash loan
    lendingPool.repay(amount, 2, address(this));

    // Confirm repayment transaction
    loanRepaidBlock[info.id] = block.number;

    // Verify that the loan has been fully repaid
    uint remainingBalance = token.balanceOf(address(this));
    require(remainingBalance == 0, "Loan not fully repaid");

    return _realizeProfit(info);
  }


  function _realizeProfit(ArbInfo memory info) internal returns (uint) {
    / Get the output amount from the trade.
    uint outputAmount = info.output;

    // Calculate the profit from the trade.
    uint profit = outputAmount - info.input;

    // Swap the profit to USDT.
    address[] memory path;
    path[0] = info.tokenOut;
    path[1] = USDT;

    uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(
    profit,
    0,
    path,
    address(this),
    block.timestamp
    );

    // Send the USDT profit to the owner.
    transferToken(USDT, owner, amounts[1]);

    // Emit the profit realized event.
    emit ProfitRealized(info.opportunityId, profit);

    // Call the profitRealizedHandler function to handle the event
    profitRealizedHandler(info.opportunityId, profit);

    return amounts[1];
  }
  // Internal views

  // Check profitability
  function checkProfitability(ArbInfo memory info) internal view returns (bool) {
    // Get the estimated gas cost of the arbitrage trade.
    uint gasCost = gasEstimator.estimateGas(info);

    // Check if the gas estimator function fails.
    if (!gasEstimator.estimateGas(info)) {
      emit ProfitabilityCheckFailed(info.opportunityId, "Gas estimation failed");
      return false;
    }

    // Check if the estimated gas cost is below the gas limit.
    if (gasCost > gasLimit) {
      return false;
    }

    // Calculate the total fees, including gas fees, exchange fees, and slippage.
    uint totalFees = gasCost + estimateExchangeFees(info) + estimateSlippage(info);

    // Check if the exchange function fails.
    if (!exchange.estimateFees(info)) {
      emit ProfitabilityCheckFailed(info.opportunityId, "Exchange fees estimation failed");
      return false;
    }

    // Calculate the profit margin.
    uint margin = (info.output - totalFees) * 100 / info.output;

    // Calculate the expected profit and loss of the trade, taking into account the stop loss and trailing stop loss orders.
    uint stopLossPrice = info.output - (info.output * info.stopLossRatio / 100);
    uint trailingStopLossPrice = stopLossPrice;
    uint expectedProfit = info.output - trailingStopLossPrice;
    uint expectedLoss = stopLossPrice - info.output;

    // Check if the expected profit is greater than or equal to the minimum profit margin and the expected loss is less than or equal to the maximum acceptable loss.
    if (expectedProfit >= minProfitMargin && expectedLoss <= maxLoss) {
      emit ProfitabilityCheckSuccess(info.opportunityId);
      return true;
    } else {
      emit ProfitabilityCheckFailed(info.opportunityId, "Trade not profitable");
      return false;
    }
  }


  // Estimate the gas cost of the arbitrage trade.

  function estimateGasCost(ArbInfo memory info) internal view returns (uint) {
    // Use a gas estimation tool to get an estimate of the gas cost of the arbitrage trade.
    uint gas = gasEstimator.estimateGas(info);

    // Return the estimated gas cost.
    return gas;
  }


  // Estimate the exchange fees associated with the arbitrage trade.

  function estimateExchangeFees(ArbInfo memory info) internal view returns (uint) {
    // Get the estimated exchange fees from the exchange.
    uint exchangeFees = exchange.estimateFees(info);

    // Return the estimated exchange fees.
    return exchangeFees;
  }

  // Estimate the slippage associated with the arbitrage trade.

  function estimateSlippage(ArbInfo memory info) internal view returns (uint) {
    // Calculate the slippage as a percentage of the output amount.
    uint slippage = info.output * slippageTolerance / 1000;

    // Return the estimated slippage.
    return slippage;
  }


  // Calculate the required margin for the arbitrage trade.
  function calculateMargin(ArbInfo memory info) internal view returns (uint) {
    // Get the value of the input amount in USD.
    uint inputValueInUSD = getValueInUSD(info.inputAmount, info.inputToken);

    // Calculate the required margin based on the value of the input amount in USD.
    uint margin;
    if (inputValueInUSD < 1000) {
      margin = inputValueInUSD / 10; // 10% margin for trades < $1000 value
    } else if (inputValueInUSD < 5000) {
      margin = inputValueInUSD / 20; // 5% margin for trades $1000-$5000
    } else if (inputValueInUSD < 10000) {
      margin = inputValueInUSD / 30; // 3.33% margin trades $5000-$10000
    } else {
      margin = inputValueInUSD / 100; // 1% margin for trades > $10,000
    }

    // Return the required margin.
    return margin;
  }

  function getValueInUSD(uint inputAmount, address token) internal view returns (uint) {
    // Get the price of the token in USD.
    uint tokenPriceUSD = priceFeed.getPrice(token);

    // Calculate the value of the input amount in USD.
    return inputAmount * tokenPriceUSD;
  }

  outputEstimate = _estimateOutput(info);
  
  function _estimateOutput(ArbInfo memory info) internal view returns (uint) {
  
    uint inputAmount = _getInputAmount(info);
  
    return priceFeed.estimateOutput(inputAmount); 

  }

  function calculateTotalFees(ArbInfo memory info) internal view returns (uint) {
    // Estimate the gas cost of the arbitrage trade.
    uint gasCost = gasEstimator.estimateGas(info);

    // Estimate the exchange fees associated with the arbitrage trade.
    uint exchangeFees = estimateExchangeFees(info);

    // Estimate the slippage associated with the arbitrage trade.
    uint slippage = outputEstimate * slippageTolerance / 1000;

    // Calculate the total fees.
    uint totalFees = gasCost + exchangeFees + slippage;

    return totalFees;
  }


  function _getInputAmount(ArbInfo memory info) internal view returns (uint) {

    uint outputEstimate = _estimateOutput(info);

    uint totalFees = calculateTotalFees(info, outputEstimate); 

    uint tradeAmount = (outputEstimate - fees) / (1 + minProfitMargin / 100);

    return tradeAmount; 

  }


  function _calculateLoanAmount(ArbInfo memory info) internal view returns (uint) {
    // Calculate the input amount for a profitable trade.
    uint inputAmount = _getInputAmount(info);

    // Calculate the total fees.
    uint totalFees = calculateTotalFees(info);

    // Calculate the margin required for the arbitrage trade.
    uint margin = calculateMargin(inputAmount);


    // Calculate the loan amount.
    uint loanAmount = inputAmount + totalFees + margin;

    return loanAmount;
  }

 
  function _getOutputAmount(ArbInfo memory info) internal view returns (uint) {
    // Get the output amount from Uniswap.
    uint[] memory amounts = uniswapRouter.getAmountsOut(
      info.outputAmount,
      info.path
    );

    // Return the output amount.
    return amounts[amounts.length - 1];
  }

   

  /* ========== VIEWS ========== */

  /**
   * @notice Calculate arbitrage profit
   * @param amountIn: Amount of tokens sent
   * @param amountOut: Amount of tokens received
   * @return uint256: Profit amount
  */
  function calculateProfit(
    uint256 amountIn,
    uint256 amountOut
  )
    public
    pure
    returns (uint256)
  {
    // Simple profit calculation
    return amountOut - amountIn; 
  }

  /* ========== ADMIN FUNCTIONS ========== */  

  function setUserRole(address userAddress, string memory role) external onlyOwner {
    userRoles[userAddress] = role;
  }  

  function registerToken(
    string memory symbol, 
    address token
  )
    external
    onlyOwner
  {
    tokens[symbol] = TokenInfo({
      name: "TODO", // Allow setting name 
      token: token
    });
  }

  function unregisterToken(string memory symbol) 
    external
    onlyOwner
  {
    delete tokens[symbol];
  }
  
  function togglePause() 
    external 
    onlyOwner 
  {
    paused = !paused;
  }

  function withdraw(address recipient, uint256 amount)
    external
    onlyOwner
  {
    transfer(recipient, amount);
  }

  function addToken(
    address token,
    string calldata name, 
    string calldata symbol    
  )
    external
    onlyRole(OWNER_ROLE)
  {
    tokens[token] = TokenInfo(name, symbol);  
  }

    function addRole(bytes32 role, address account) 
    external 
    onlyRole(OWNER_ROLE)
  {
    userRoles[account] = role;
  }

  function removeRole(bytes32 role, address account)
    external
    onlyRole(OWNER_ROLE) 
  {
    userRoles[account] = bytes32(0);
  }  

  /* ========== SAFETY ========== */

  function transfer(address recipient, uint amount) internal {
    (bool success, ) = recipient.call{value: amount}("");
    require(success, "Transfer failed");
  }

 
 
  /* ========== UPGRADABILITY ========== */

	// Proxy contract

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
  }

  /* ========== END OF SMART CONTRACT ========== */

}