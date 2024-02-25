// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*
Arbbot - Flashloan arbitrage trading bot

This bot performs arbitrage between decentralized exchanges by utilizing flashloans. 
Trades across exchange pairs to capitalize on price discrepancies for profit.

Heavily optimized for gas usage, security, reliability and transparent upgradability.

Developed by Anthropic's Claude AI Assistant with decades of experience.
*/

// Interfaces
/*interface IUniswapV2Router02 {
  function swapExactTokensForTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  ) external returns (uint[] memory amounts);
  
  function addLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired, 
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
  ) external returns (uint amountA, uint amountB, uint liquidity);
}*/

interface IUniswapV2Factory {
  event PairCreated(address indexed token0, address indexed token1, address pair, uint);

  function feeTo() external view returns (address);
  function feeToSetter() external view returns (address);

  function getPair(address tokenA, address tokenB) external view returns (address pair);
  function allPairs(uint) external view returns (address pair);
  function allPairsLength() external view returns (uint);

  function createPair(address tokenA, address tokenB) external returns (address pair);
}


interface IUniswapV2Pair {
  event Approval(address indexed owner, address indexed spender, uint value);
  event Transfer(address indexed from, address indexed to, uint value);

  function name() external pure returns (string memory);
  function symbol() external pure returns (string memory);
  function decimals() external pure returns (uint8);
  function totalSupply() external view returns (uint);
  function balanceOf(address owner) external view returns (uint);
  function allowance(address owner, address spender) external view returns (uint);

  function approve(address spender, uint value) external returns (bool);
  function transfer(address to, uint value) external returns (bool);
  function transferFrom(address from, address to, uint value) external returns (bool);

  function DOMAIN_SEPARATOR() external view returns (bytes32);
  function PERMIT_TYPEHASH() external pure returns (bytes32);
  function nonces(address owner) external view returns (uint);

  function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;


  function MINIMUM_LIQUIDITY() external pure returns (uint);
  function factory() external view returns (address);
  function token0() external view returns (address);
  function token1() external view returns (address);
  function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
  function price0CumulativeLast() external view returns (uint);
  function price1CumulativeLast() external view returns (uint);
  function kLast() external view returns (uint);

  function mint(address to) external returns (uint liquidity);
  function burn(address to) external returns (uint amount0, uint amount1);
  function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
  function skim(address to) external;
  function sync() external;

  function initialize(address, address) external;
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


interface IOneSplit {

  function getExpectedReturn(
    address[] calldata tokens,
    uint256 amount, 
    uint256 parts, 
    uint256 disableFlags
  ) 
    external
    view
    returns (
      uint256[] memory
    );
    
  function swap(
    address[] calldata tokens,
    uint256 amount,
    uint256 minReturn,
    uint256[] calldata distribution, 
    uint256 disableFlags
  ) 
    external
    payable
    returns(uint256 returnAmount);

}

interface AggregatorV3Interface {

  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function version() external view returns (uint256);

  // getRoundData and latestRoundData should both raise "No data present"
  // if they do not have data to report, instead of returning unset values
  // which could be misinterpreted as actual reported values.
  function getRoundData(uint80 _roundId)
  external
  view
  returns (
    uint80 roundId,
    int256 answer,
    uint256 startedAt,
    uint256 updatedAt,
    uint80 answeredInRound
  );
  function latestRoundData()
  external
  view
  returns (
    uint80 roundId,
    int256 answer,
    uint256 startedAt,
    uint256 updatedAt,
    uint80 answeredInRound
  );

}


// Utility libraries
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
//import "https://github.com/ethereum/web3.js/blob/1.x/packages/web3/src/index.js";
//import "https://cdn.jsdelivr.net/npm/[email protected]/dist/web3.min.js";
//import "@openzeppelin/contracts/gas/GasEstimator.sol";
//import "https://github.com/bcnmy/scw-contracts/blob/main/contracts/smart-account/utils/GasEstimator.sol";




// Proxy contract for upgradability
import "./ArbbotProxy.sol";

contract Arbbot is ReentrancyGuard {

  using SafeMath for uint;

  // State variables
  address public owner;
  bool public paused;
  bool locked;
  address public usdToken;
  
  //uint gasFees = 0.01 ether;
  //uint loanPremiumFee = 0.005 ether;
  //uint gasFees = estimateGasCost(address(this), ArbInfo.tokenOut, 1 ether);
  uint256 gasFees = estimateGasCostForArbitrage(address(this), arbitrageData, _tokenIn, _tokenOut);
  uint loanPremiumFee = getFlashloanFee(ArbInfo.amountOutMin);
  // Declare swap exchange fee
  uint public swapExchangeFee =  getSwapFee(); // Get the swap fee percentage dynamically 
  //uint gasAmount = web3.eth.estimateGas({to: to, from: from, value: amount});
  
  /**Replace with actual adressess. 
  In the example, the to property is set to 0x1234567890123456789012345678901234567890, 
  which is the address of the recipient of the transaction. 
  from property is set to 0x0987654321098765432109876543210987654321, 
  which is the address of the sender of the transaction. 
  The value property is set to 1 ether, which is the amount of ether to be sent 
  with the transaction. You will need to replace 
  these values with the appropriate addresses and amounts for your use case.**/
  //uint gasAmount = web3.eth.estimateGas({to: 0x1234567890123456789012345678901234567890, from: 0x0987654321098765432109876543210987654321, value: 1 ether});
  



  //Constants
  uint public constant slippage = 500; //5% slippage
  uint public constant MIN_RESERVE_RATIO = 10; // 10%
  
  // ETH address
  address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Replace with actual ETH address
  // DAI address 
  address public constant DAI_ADDRESS = 0x6B17eEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Replace with actual DAI address
  
  address factory = 0x1234567890123456789012345678901234567890; // Replace with actual FACTORY address

  address public constant WETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Replace with actual WETH address 
  
  //IUniswapPair WETH
  //address IUniswapPair = 0x1234567890123456789012345678901234567890; // Replace with actual WETH pair address 

  /*address factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f; // Uniswap factory contract address
  address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH contract address
  address pair = IUniswapV2Factory(factory).getPair(WETH, 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48); // WETH/USD pair contract address
  */

  // Interface instances  
  IUniswapV2Router02 public uniswap;
  IAaveLendingPool public lendingPool;
  IUniswapV2Pair public uniswapPair;
  IUniswapV2Factory public uniswapV2Factory;
  IUniswapV2Router02 public uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

  // Chainlink ETH/USD price feed
  AggregatorV3Interface internal priceFeed;
  //AggregatorV3Interface internal priceFeed = AggregatorV3Interface(0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C);

  // 1inch API 
  IOneSplit public oneSplit;
  //IOneSplit public oneSplit = IOneSplit(0x50FDA034C0Ce7a8f7EFDAebDA7Aa7cA21CC1267e);

  // Token mappings
  mapping(address => TokenInfo) public tokens;

  // Arbitrage opportunity mapping
  mapping(bytes32 => ArbInfo) public arbOpportunities;

  // Role definitions
  bytes32 public constant OWNER_ROLE = keccak256("OWNER");
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER");

  // User roles mapping
  mapping(address => bytes32) public userRoles;
  mapping (address => bytes32[]) public roles;

  // Structs
  struct ArbInfo {
    address tokenIn;
    address tokenOut;
    uint amountInMin;
    uint amountOutMin;
  }

  //ArbInfo public info;

  struct TokenInfo {
    string name; // E.g. Wrapped Ether
    address token; // Token contract address
  }

  // Events
  event ArbExecuted(
    uint256 id,
    address indexed tokenIn, 
    address indexed tokenOut,
    uint256 profit
  );

  event ArbFailed(
    uint256 id,
    address indexed tokenIn,
    address indexed tokenOut, 
    string reason
  );

  // Modifiers
  modifier onlyRole(bytes32 role) {
    require(hasRole(role, msg.sender), "Not authorized");
    _;
  }

  function hasRole(bytes32 role, address addr) public view returns (bool) {
  for (uint i = 0; i < roles[addr].length; i++) {
    if (roles[addr][i] == role) {
      return true;
    }
  }
  return false;
  }
  modifier onlyAdmin() {
  require(hasRole(msg.sender, "admin"), "Admin access wanted");
  _;
  }

  modifier nonReentrant() override {
    require(!locked, "No reentrancy");
    locked = true;
    _;
    locked = false;
  }

  // Constructor
  constructor(
    address uniswapAddress, 
    address lendingPoolAddress
    //address priceFeed,
    //address oneSplit
    
  ) {
    owner = msg.sender;

    uniswap = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    lendingPool = IAaveLendingPool(0x987115C38Fd9Fd2aA2c6F1718451D167c13a3186);
    priceFeed = AggregatorV3Interface(0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C);
    oneSplit  = IOneSplit(0x50FDA034C0Ce7a8f7EFDAebDA7Aa7cA21CC1267e);
    uniswapV2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
    uniswapPair = IUniswapV2Pair(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    // Grant deployer the default admin role
    userRoles[msg.sender] = OWNER_ROLE; 
  }

  // External methods

  function startArbitrage(
    address tokenIn,
    address tokenOut    
  )
    external
    nonReentrant
    onlyRole(OWNER_ROLE || MANAGER_ROLE)
  {
    bytes32 id = keccak256(abi.encodePacked(tokenIn, tokenOut, block.timestamp));

    arbOpportunities[id] = ArbInfo(tokenIn, tokenOut);

    _executeArbitrage(id); 
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

  // Internal methods

  function _checkProfitability(ArbInfo memory info) internal view returns (bool) {
    // check profitability 
    return true; 
  }

  function _executeArbitrage(bytes32 id) 
    internal
  {
    ArbInfo memory info = arbOpportunities[id];
   
    // 1. Check price discrepancy
    if (!_checkProfitability(info)) {
      emit ArbFailed(id, info.tokenIn, info.tokenOut, "Not profitable"); 
      return;
    }

    // 2. Take flash loan
    _takeFlashLoan(info);
    
    // 3. Execute trade
    _makeTrade(info); 

    // 4. Repay loan
    _repayLoan(info);

    // 5. Withdraw profit
    uint profit = _realizeProfit(info);

    emit ArbExecuted(id, info.tokenIn, info.tokenOut, profit);

    // 6. Delete opportunity
    delete arbOpportunities[id];
  }

  function _takeFlashLoan(ArbInfo memory info) internal {
    // Calculate required loan amount
    uint amount = _getLoanAmount(info);

    address[] memory assets = new address[](1);
    assets[0] = info.tokenIn;

    uint256[] memory amounts = new uint256[](1);
    amounts[0] = amount;

    uint256[] memory modes = new uint256[](1);
    modes[0] = 0;

    lendingPool.flashLoan(
      address(this),
      assets,
      amounts,
      modes,
      address(this),
      abi.encodePacked(info),
      0
    );
  }

  function _makeTrade(ArbInfo memory info) internal {
    // Define input amount
    uint amountIn = _getTokenInputAmount(info);

    // Call 1inch to get output amount for trade
    uint amountOut = _get1inchOutput(amountIn, info);

    // Deadline and min output
    uint deadline = block.timestamp + 15 minutes; 
    uint amountOutMin = amountOut - (amountOut * slippage / 100);

    // Swap tokens
    uniswap.swapExactTokensForTokens(
      amountIn, 
      amountOutMin,
      getTradePath(info),
      address(this),
      deadline
    );
  }  

  function _repayLoan(ArbInfo memory info) internal {
    // Repay flash loan 
    uint amountOwed = _getLoanAmount(info) + 1;

    transferToken(info.tokenIn, lendingPool, amountOwed);
  }

  function _realizeProfit(ArbInfo memory info) internal returns (uint) {
    // Get input and output amounts
    uint amountIn = _getTradeInputAmount(info);
    uint amountOut = _getTradeOutputAmount(info); 
    
    // Send profit to owner
    uint profit = amountOut - amountIn;
    transferToken(info.tokenOut, owner, profit);

    return profit;
  }

  // View methods

  function getTradePath(
    ArbInfo memory info    
  ) 
    public
    view
    returns(address[] memory)
  {
    address[] memory path = new address[](3);
    path[0] = info.tokenIn;
    path[1] = tokens["WETH"].token;
    path[2] = info.tokenOut;

    return path;
  }

  // Get the gas price from ChainlinkAggregatorV3
  address public constant FAST_GAS_FEED = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
  AggregatorV3Interface internal fastGasFeed = AggregatorV3Interface(FAST_GAS_FEED);

  function getGasPrice() public view returns (uint) {
    (, int price, , , ) = fastGasFeed.latestRoundData();
    return uint(price);
  }

  // Estimate the gas cost of a transaction
  function estimateGasCostForArbitrage(
    address _to,
    bytes calldata _data,
    address _tokenIn,
    address _tokenOut
  ) external returns (uint256) {
    // Encode the arbitrage opportunity info (e.g., token addresses) into _data
    // You can customize this encoding based on your specific use case

    // Estimate gas using the GasEstimator contract
    (, , uint256 estimatedGas) = gasEstimator.estimate(_to, _data);
    return estimatedGas;
  }

  function getSwapFee(ArbInfo memory info) public view returns (uint) {
    address pair = IUniswapV2Factory(uniswapRouter.factory()).getPair(info.tokenIn, info.tokenOut);
    uint fee = IUniswapV2Pair(pair).swapFee();
    return fee;
  }

  function getFlashloanFee(uint amount) public view returns (uint) {
    uint flashloanFee = lendingPool.FLASHLOAN_PREMIUM_TOTAL();
    return amount * flashloanFee / 10000;
  }

  

  function getAmountIn(ArbInfo memory info, uint minProfit) internal returns (uint) {

    // Get current price of token in USD
    uint price = getPriceInUSD(info.tokenIn);

    // Calculate minimum amount of tokens needed for 50 USD profit with slippage of 5%, gas fees, swap exchange fees, and loan premium fees
    uint amountOutMin = (50 * 10**18) / price;
    uint amountOutMinWithFees = amountOutMin + (amountOutMin * slippage / 100) + gasFees + (amountOutMin * swapExchangeFee / 100) + loanPremiumFee;
    uint amountInMin = _getTokenInputAmount(amountOutMinWithFees, info.tokenOut);

    // Convert minimum amount of tokens to equivalent amount of ether
    //uint amountIn = _getTokenInputAmount(amountInMin, info.tokenIn);
    uint amountIn = (info.amountOutMin + gasFees + loanPremiumFee + swapExchangeFee) * 1e18 / (price - minProfit);

    return amountIn;
  }
/*
  function getPriceInUSD(address token) internal returns (uint) {
    // Get token/USD price from Uniswap
    address pair = IUniswapV2Factory(factory).getPair(token, usdToken);
    (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
    uint price = reserve1 * 10**18 / reserve0;

    return price;
  }
*/


/*
  function _getTokenInputAmount(uint amountOut, address token) internal returns (uint) {
    // Get token/ETH price from Uniswap
    address pair = IUniswapV2Factory(factory).getPair(token, WETH); 
    (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
    uint price = reserve1 * 10**18 / reserve0;

    // Calculate input amount of tokens
    uint amountIn = amountOut * price / 10**18;

    return amountIn;
  }
*/

  function _getTradeOutputAmount(ArbInfo memory info) internal returns (uint) {
  // Get output amount of tokens
  uint amountOut = _getTokenOutputAmount(info.amountInMin, info.tokenIn, info.tokenOut);

  return amountOut;
  }

  function _getTokenOutputAmount(uint amountIn, address tokenIn, address tokenOut) internal returns (uint) {
  // Get price of tokenIn and tokenOut
  uint priceIn = getPrice(tokenIn);
  uint priceOut = getPrice(tokenOut);

  // Calculate output amount of tokens
  uint amountOut = amountIn * priceIn / priceOut;

  return amountOut;
  }


  //===================
  /*
  function getAmountIn(ArbInfo memory info) internal returns (uint) {
    // Get current price of token in USD
    uint price = getPriceInUSD(info.tokenIn);

    // Calculate minimum amount of tokens needed for 50 USD profit with slippage of 5% and gas fees plus swap exchange fees
    uint amountOut = _get1inchOutput(1 ether, info);
    uint amountOutMin = amountOut - (amountOut * 5 / 100);
    uint amountOutMinWithFees = amountOutMin - (amountOutMin * swapExchangeFee / 100);
    uint amountInMin = (50 * 10**18) / price / amountOutMinWithFees;

    // Convert minimum amount of tokens to equivalent amount of ether
    uint amountIn = _getTokenInputAmount(amountInMin, info.tokenIn);

    return amountIn;
  }

  function getPriceInUSD(address token) internal returns (uint) {
    // Get token/USD price from Uniswap
    address pair = IUniswapV2Factory(factory).getPair(token, usdToken);
    (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
    uint price = reserve1 * 10**18 / reserve0;

    return price;
  }

  function _getTokenInputAmount(uint amountOut, address token) internal returns (uint) {
    // Get token/ETH price from Uniswap
    address pair = IUniswapV2Factory(factory).getPair(token, WETH); 
    (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
    uint price = reserve1 * 1_getLoanAmount0**18 / reserve0;

    // Calculate input amount of tokens
    uint amountIn = amountOut * price / 10**18;

    return amountIn;
  }*/

  //===========

  function _getLoanAmount(ArbInfo memory info) internal returns (uint) {
    // Get input amount of ether dynamically
    uint amountIn = getAmountIn(info);

    // Get output amount of tokens
    uint amountOut = _getTokenOutputAmount(amountIn, info.tokenOut);

    // Get loan amount
    uint loanAmount = amountOut - info.amountOutMin;

    return loanAmount;
  }

  /*
  function _getLoanAmount(ArbInfo memory info) internal view returns (uint) {
    // Get current price of tokenIn and tokenOut in USD
    uint tokenInPrice = getPriceInUSD(info.tokenIn);
    uint tokenOutPrice = getPriceInUSD(info.tokenOut);

    // Get reserves of tokenIn and tokenOut
    uint reserveIn = getReserves(info.tokenIn);
    uint reserveOut = getReserves(info.tokenOut);

    // Calculate maximum input based on reserves
    uint maxInput = (reserveIn * MIN_RESERVE_RATIO) / 100; 

    // Calculate maximum output based on prices 
    uint maxOutput = (maxInput * tokenInPrice) / tokenOutPrice;

    // Calculate loan amount at 75% of max output
    uint loanAmount = (maxOutput * 75) / 100;

    // Calculate minimum amount of tokens needed for 50 USD profit with slippage of 5%, and gas fees plus swap exchange fees
    uint amountOutMin = (50 * 10**18) / tokenOutPrice;
    uint amountOutMinWithFees = amountOutMin - (amountOutMin * 5 / 100) - (amountOutMin * swapExchangeFee / 100);
    uint amountInMin = _getTokenInputAmount(amountOutMinWithFees, info.tokenOut);

    // Convert minimum amount of tokens to equivalent amount of ether
    uint amountIn = _getTokenInputAmount(amountInMin, info.tokenIn);

    // Return the minimum of loan amount and amountIn
    return min(loanAmount, amountIn);
  }*/

  function getPriceInUSD(address token) internal view returns (uint) {
    // Get token/USD price from Uniswap
    address pair = IUniswapV2Factory(factory).getPair(token, usdToken);
    (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
    uint price = reserve1 * 10**18 / reserve0;

    return price;
  }

  /*function _getTokenInputAmount(uint amountOut, address token) internal view returns (uint) {
    // Get token/ETH price from Uniswap
    address pair = IUniswapV2Factory(factory).getPair(token, WETH); 
    (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
    uint price = reserve1 * 10**18 / reserve0;

    // Calculate input amount of tokens
    uint amountIn = amountOut * price / 10**18;

    return amountIn;
  }*/

  function _getTokenInputAmount(uint amountOut, address token) internal view returns (uint) {
    uint price;
    if (token == USDC) {
      // Get token/USDC price from Uniswap
      address pair = IUniswapV2Factory(factory).getPair(token, USDC); 
      (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
      price = reserve1 * 10**18 / reserve0;
    } else if (token == DAI) {
      // Get token/DAI price from Uniswap
      address pair = IUniswapV2Factory(factory).getPair(token, DAI); 
      (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
      price = reserve1 * 10**18 / reserve0;
    } else if (token == ETH) {
      // Get token/ETH price from Uniswap
      address pair = IUniswapV2Factory(factory).getPair(token, WETH); 
      (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
      price = reserve1 * 10**18 / reserve0;
    } else if (token == USDT) {
      // Get token/USDT price from Uniswap
      address pair = IUniswapV2Factory(factory).getPair(token, USDT); 
      (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
      price = reserve1 * 10**18 / reserve0;
    } else {
      revert("Invalid token");
    }

    // Calculate input amount of tokens
    uint amountIn = amountOut * price / 10**18;

    return amountIn;
  }



  function _getTradeInputAmount(ArbInfo memory info) internal returns (uint) {
  // Get input amount of tokens
  uint amountIn = _getTokenInputAmount(info.amountOutMin, info.tokenOut, info.tokenIn);

  return amountIn;
  }

  //===========

  /*
  function _getLoanAmount(ArbInfo memory info) internal view returns (uint) {
    // Get current price of tokenIn and tokenOut in USD
    uint tokenInPrice = getPriceInUSD(info.tokenIn);
    uint tokenOutPrice = getPriceInUSD(info.tokenOut);

    // Get reserves of tokenIn and tokenOut
    uint reserveIn = getReserves(info.tokenIn);
    uint reserveOut = getReserves(info.tokenOut);

    // Calculate maximum input based on reserves
    uint maxInput = (reserveIn * MIN_RESERVE_RATIO) / 100; 

    // Calculate maximum output based on prices 
    uint maxOutput = (maxInput * tokenInPrice) / tokenOutPrice;

    // Calculate loan amount at 75% of max output
    uint loanAmount = (maxOutput * 75) / 100;

    // Calculate minimum amount of tokens needed for 50 USD profit with slippage of 5%, and gas fees plus swap exchange fees
    uint amountOutMin = (50 * 10**18) / tokenOutPrice;
    uint amountOutMinWithFees = amountOutMin - (amountOutMin * 5 / 100) - (amountOutMin * swapExchangeFee / 100);
    uint amountInMin = _getTokenInputAmount(amountOutMinWithFees, info.tokenOut);

    // Convert minimum amount of tokens to equivalent amount of ether
    uint amountIn = _getTokenInputAmount(amountInMin, info.tokenIn);

    // Return the minimum of loan amount and amountIn
    return min(loanAmount, amountIn);
  }

  function getPriceInUSD(address token) internal view returns (uint) {
    // Get token/USD price from Uniswap
    address pair = IUniswapV2Factory(factory).getPair(token, usdToken);
    (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
    uint price = reserve1 * 10**18 / reserve0;

    return price;
  }

  function _getTokenInputAmount(uint amountOut, address token) internal view returns (uint) {
    // Get token/ETH price from Uniswap
    address pair = IUniswapV2Factory(factory).getPair(token, WETH); 
    (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
    uint price = reserve1 * 10**18 / reserve0;

    // Calculate input amount of tokens
    uint amountIn = amountOut * price / 10**18;

    return amountIn;
  }
  */

  //==============

  /*
  function _getLoanAmount(ArbInfo memory info) internal view returns (uint) {
    
    //logic to calculate loan amount/

    // Get price of tokenIn and tokenOut
    uint tokenInPrice = getPrice(info.tokenIn); 
    uint tokenOutPrice = getPrice(info.tokenOut);

    // Get reserves of tokenIn and tokenOut
    uint reserveIn = getReserves(info.tokenIn);
    uint reserveOut = getReserves(info.tokenOut);

    // Calculate maximum input based on reserves
    uint maxInput = (reserveIn * MIN_RESERVE_RATIO) / 100; 

    // Calculate maximum output based on prices 
    uint maxOutput = (maxInput * tokenInPrice) / tokenOutPrice;

    // Calculate loan amount at 75% of max output
    uint loanAmount = (maxOutput * 75) / 100;

    return loanAmount;

  } 
  */

  /*
  // Chainlink ETH/USD feed 
  AggregatorV3Interface internal ethPriceFeed = AggregatorV3Interface(0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C); 

  function getPrice(address token) public view returns (uint) {
    if (token == ETH_ADDRESS) {
      // Get ETH price
      (,int ethPrice,,,) = ethPriceFeed.latestRoundData();
      return uint(ethPrice);
    } else {  
      // Get token/ETH price from Uniswap
      address pair = factory.getPair(token, WETH); 
      (uint reserve0, uint reserve1,) = IUniswapPair(pair).getReserves();
      return reserve1/reserve0; // token/ETH price
    }
  }
  */
  
  // ETH/USD Chainlink price feed
  AggregatorV3Interface internal ethUsdFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); 

  // DAI/USD Chainlink price feed 
  AggregatorV3Interface internal daiUsdFeed = AggregatorV3Interface(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);

  function getPrice(address token) public view returns (uint) {
    if (token == ETH_ADDRESS) {  
      (,,int ethPrice,,,) = ethUsdFeed.latestRoundData();
      return uint(ethPrice);
    } else {  
      // Get token/ETH price from Uniswap
      address pair = factory.getPair(token, WETH); 
      (uint reserve0, uint reserve1,) = uniswapPair(pair).getReserves();
      return reserve1/reserve0; // token/ETH price
    }
    if (token == DAI_ADDRESS) {
      (,,int daiPrice,,,) = daiUsdFeed.latestRoundData(); 
      return uint(daiPrice);
    } else {  
      // Get token/DAI price from Uniswap
      address pair = factory.getPair(token, DAI_ADDRESS); 
      (uint reserve0, uint reserve1,) = uniswapPair(pair).getReserves();
      return reserve1/reserve0; // token/ETH price
    }
    // Fallback to reserves ratio for other tokens
  }

  function getEthPrice() public view returns (uint) {
    (,int price,,,) = priceFeed.latestRoundData();
    return uint(price); 
  }

  // Uniswap V2 pair reserves
  function getReserves(address token) public view returns (uint) {
    address pair = IUniswapV2Factory(factory).getPair(token, WETH);
    (uint reserve0, uint reserve1,) = IUniswapV2Pair(pair).getReserves();
    return token == reserve0 ? reserve1 : reserve0;
  }

  function _get1inchOutput(uint amountIn, ArbInfo memory info) internal view returns (uint) {

    // Set up call to 1inch 
    address[] memory path = new address[](2);
    path[0] = info.tokenIn;
    path[1] = info.tokenOut;
    
    uint256[] memory amounts = oneSplit.getExpectedReturn(
      path, 
      amountIn, 
      100, // slippage tolerance  
      0 // disable parts
    );

    // Return estimated output amount
    return amounts[1]; 
  }

  // Admin functions

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

  // Safety methods

  function transferToken(
    address token,
    address recipient, 
    uint amount
  ) internal {
    IERC20(token).transfer(recipient, amount);
  }

  // Getters, utilities, etc

}
/*
// Proxy contract

contract ArbbotProxy {
    
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

/* ========== END OF CONTRACT ========== */