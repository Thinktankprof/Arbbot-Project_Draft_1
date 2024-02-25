// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract ArbbotUser {

    address public owner;
    //uint256 public profitPayoutPercentage;
    uint256 public paymentInterval; // Payment interval in seconds
    uint256 public lastPayoutTimestamp;
    

    // Mapping to store the subscription category for each user
    mapping(address => SubscriptionCategory) public userSubscriptionCategories;

    // Mapping to store the cryptographic hash key for each subscription category
    mapping(SubscriptionCategory => bytes32) public subscriptionCategoryHashKeys;

    // Mapping to store subscription details for each category
    mapping(SubscriptionCategory => SubscriptionDetails) public subscriptionCategories;
    
    // Mapping to store the used hash keys or tokens
    mapping(bytes32 => bool) public usedHashKeys;

    mapping(address => Trade[]) public userTrades;
   
    mapping(address => uint256) public dailyProfits;

    // Mapping to store user balances
    mapping(address => uint256) public userBalances;

    mapping(address => TokenPair) public userTradePairAddresses;

    struct TokenPair {
    address[3] tokenIn;
    address[3] tokenOut;
    bool locked; // Optional: Flag to indicate if the user can update their addresses
    }

    // Define User Struct
    struct User {
    uint256 id;
    SubscriptionCategory subscription;
    address payable payoutAddress; // address payable to allow sending funds
    uint256 subscriptionExpiry;
    mapping(address => TokenPair) userTradePairAddresses;
    }

    // Enum to represent subscription categories
    enum SubscriptionCategory {
    Silver,
    Gold,
    Diamond,
    Legacy,
    NewCategory
    }

    // A struct to store trade details and a mapping to track daily profits
    struct Trade {
        address user;
        uint256 amount;
        // Add other trade details as needed
    }

    enum ProfitCalculationMethod { DailyProfit, TermAmount }
    ProfitCalculationMethod public calculationMethod;

    /*
    constructor() {
        owner = msg.sender;
        profitPayoutPercentage = 5; // Default profit payout percentage (adjust as needed)
        paymentInterval = 1 days; // Default payment interval (adjust as needed)
        calculationMethod = ProfitCalculationMethod.DailyProfit; // Default calculation method
        lastPayoutTimestamp = block.timestamp;
    }
    */

    constructor(string memory name, string memory email, 
    SubscriptionCategory subscription, 
    address payable payoutAddress, 
    uint256 subscriptionDuration) {
    id = _getNextUserID();
    // ... other initialization logic
    owner = msg.sender;
        profitPayoutPercentage = 5; // Default profit payout percentage (adjust as needed)
        paymentInterval = 1 days; // Default payment interval (adjust as needed)
        calculationMethod = ProfitCalculationMethod.DailyProfit; // Default calculation method
        lastPayoutTimestamp = block.timestamp;
    }

    /*// Struct to store subscription details
    struct SubscriptionDetails {
        uint256 duration; // Duration in days
        uint256 expiryTimestamp; // Expiry timestamp
        bool isPaid; // Boolean flag indicating whether it's a paid subscription
        uint256 termAmount; // Term amount for paid subscriptions
        uint256 profitPercentage; // Profit percentage share payout for the subscription category
    }
    */
    
    //improved struct SubscriptionDatails version
    struct SubscriptionDetails {
    uint256 duration;
    uint256 expiryTimestamp;
    bool isPaid;
    uint256 termAmount; // Term amount for paid subscriptions
    uint256 profitPercentage; // Profit percentage share payout for the subscription category
    uint256 lastPaymentRoundAmount; // Payout profit percentage + term amount used for percentage calculation
    }
    


    /* ========= User Subscription Category ========= */

    // Silver category
    struct SilverSubscription {
        uint256 subscriptionAmount; // $100 default
        uint256 termAmount; // Profit percentage calculation method
        uint256 subscriptionDuration; // 3 months default
        uint256 payoutProfitPercentage;
        uint256 numPaymentRounds; // Based on payout intervals and subscription duration
        uint256 payoutInterval; // Payment intervals or rate = time
        uint256 lastPayment; // Payout percentage amount + term amount used for percentage calculation
    }

    // Gold category
    struct GoldSubscription {
        uint256 subscriptionAmount; // $200 default
        uint256 termAmount; // Profit percentage calculation method
        uint256 subscriptionDuration; // 6 months default
        uint256 payoutProfitPercentage;
        uint256 numPaymentRounds; // Based on subscription duration
        uint256 payoutInterval; // Payment intervals or rate = time
        uint256 lastPayment; // Payout profit percentage + term amount used for percentage calculation
    }

    // Diamond category
    struct DiamondSubscription {
        uint256 termAmount; // Calculate daily profit percentage method
        uint256 subscriptionDuration; // Custom subscription duration (12 month default)
        uint256 payoutProfitPercentage; // Custom payout percentage (50% default)
        uint256 payoutInterval; // Custom payment intervals
        uint256 lastPayment; // Payout percentage amount + fixed amount used for percentage calculation
        uint256 numPaymentRounds; // Based on subscription duration
    }

    // Legacy category
    struct LegacySubscription {
        uint256 termAmount; // Calculate daily profit percentage method
        uint256 subscriptionDuration; // Custom subscription duration (12 month default auto renewal)
        uint256 payoutProfitPercentage; // Custom payout percentage (80% default to App Owner)
        uint256 payoutInterval; // Custom payment intervals
        uint256 numPaymentRounds; // Number of payment rounds executed based on specified duration or updated to current time
        uint256 totalProfitAmount; // Total profit amount realized for the app instance based on specified duration or updated to current time
    }

    /*========User hashkey cryptographic generation ========*/ 

    // Function to generate a unique cryptographic hash key for a subscription category
    function generateHashKey(SubscriptionCategory category) external onlyOwner returns (bytes32) {
        bytes32 hashKey = keccak256(abi.encodePacked(category));
        subscriptionCategoryHashKeys[category] = hashKey;
        return hashKey;
    }

    // Function to generate a unique cryptographic hash key for subscription renewal
    function generateRenewalHashKey(address user, SubscriptionCategory category) external onlyOwner returns (bytes32) {
        bytes32 hashKey = keccak256(abi.encodePacked(user, category, "renewal"));
        require(!usedHashKeys[hashKey], "Hash key or token has already been used");
        usedHashKeys[hashKey] = true;
        return hashKey;
    }

    // Function to generate a unique cryptographic hash key for subscription upgrade
    function generateUpgradeHashKey(address user, SubscriptionCategory category) external onlyOwner returns (bytes32) {
        bytes32 hashKey = keccak256(abi.encodePacked(user, category, "upgrade"));
        require(!usedHashKeys[hashKey], "Hash key or token has already been used");
        usedHashKeys[hashKey] = true;
        return hashKey;
    }

    // Function to apply a subscription category to a user account
    function applySubscriptionCategory(address user, bytes32 hashKey) external onlyOwner {
        SubscriptionCategory category = getCategoryFromHashKey(hashKey);
        userSubscriptionCategories[user] = category;
    }

    // Function to get the subscription category from a cryptographic hash key
    function getCategoryFromHashKey(bytes32 hashKey) internal view returns (SubscriptionCategory) {
        for (uint256 i = 0; i < uint256(SubscriptionCategory.NumCategories); i++) {
        SubscriptionCategory category = SubscriptionCategory(i);
        if (subscriptionCategoryHashKeys[category] == hashKey) {
                return category;
            }
        }
        revert("Invalid hash key");
    }

    // Function to validate the uniqueness of a hash key or token
    function validateHashKey(bytes32 hashKey) internal view {
        require(!usedHashKeys[hashKey], "Hash key or token has already been used");
    }

    /*// Function to renew a user's subscription
    function renewSubscription(address user, uint256 duration) external onlyOwner {
        SubscriptionCategory category = userSubscriptionCategories[user];
        validateHashKey(subscriptionCategoryHashKeys[category]);
        validateHashKey(subscriptionCategoryHashKeys[category]);

        uint256 expiryTimestamp = calculateExpiryTimestamp(duration);
        SubscriptionDetails storage details = subscriptionCategories[category];
        details.expiryTimestamp = expiryTimestamp;
    }*/

    // Function to renew a user's subscription using a hash key
    function renewSubscription(address user, bytes32 hashKey, uint256 duration) external onlyOwner {
        SubscriptionCategory category = getCategoryFromHashKey(hashKey);
        validateHashKey(hashKey);

        // Calculate the subscription expiry timestamp
        uint256 expiryTimestamp = calculateExpiryTimestamp(duration);
        SubscriptionDetails storage details = subscriptionCategories[category];
        details.expiryTimestamp = expiryTimestamp;

        // Mark the hash key as used
        usedHashKeys[hashKey] = true;
    }

    // Function to upgrade a user's subscription using a hash key
    function upgradeSubscription(address user, bytes32 hashKey) external onlyOwner {
        SubscriptionCategory category = getCategoryFromHashKey(hashKey);
        validateHashKey(hashKey);
        userSubscriptionCategories[user] = category;

        // Mark the hash key as used
        usedHashKeys[hashKey] = true;
    }

    /*// Function to upgrade a user's subscription
    function upgradeSubscription(address user, bytes32 hashKey) external onlyOwner {
        validateHashKey(hashKey);
        SubscriptionCategory category = getCategoryFromHashKey(hashKey);
        userSubscriptionCategories[user] = category;
    }*/

    // Function to calculate the subscription expiry timestamp
    function calculateExpiryTimestamp(uint256 duration) internal view returns (uint256) {
        return block.timestamp + duration;
    }

    /*// Function to check if a user is eligible for Diamond status
    function isDiamondUser(address user) internal view returns (bool) {
        return user == owner;
    }
    */

    // Function to calculate the number of payment rounds based on the subscription duration
    function calculateNumPaymentRounds(uint256 subscriptionDuration, uint256 payoutInterval) internal view returns (uint256) {
        return subscriptionDuration / payoutInterval;
    }

    
    // Function to calculate the user's share of profit based on daily profit 
    function calculateProfitShare(uint256 termAmount, uint256 dailyProfit) internal view returns (uint256) { 
        if (calculationMethod == ProfitCalculationMethod.DailyProfit) { 
        return (dailyProfit * profitPayoutPercentage) / 100; } 
        else if (calculationMethod == ProfitCalculationMethod.TermAmount) { 
        return calculateProfitShareTermAmount(termAmount); } 
        else { revert("Invalid profit calculation method"); } 
    } 

    // Function to calculate the user's share of profit based on daily profit 
    function calculateProfitShareDailyProfit(uint256 termAmount, uint256 dailyProfit) internal view returns (uint256) { 
    return (dailyProfit * profitPayoutPercentage) / 100; } 


    // Function to calculate the user's share of profit based on term amount 
    function calculateProfitShareTermAmount(uint256 termAmount) internal view returns (uint256) { 
    return (termAmount * profitPayoutPercentage) / 100; }


    // Function to calculate the last payment amount based on the profit percentage and term amount
    function calculateLastPayment(uint256 termAmount, uint256 profitPercentage) internal view returns (uint256) {
        return termAmount * profitPercentage / 100;
    }
    
    /*======= Register User =============*/
    

    // Function to register a user with a subscription hash key
    function registerUser(
    string memory name,
    string memory email,
    bytes32 hashKey,
    address payoutAddress
    ) external {
    SubscriptionCategory category = getCategoryFromHashKey(hashKey);
    validateHashKey(hashKey);

    // Calculate the subscription expiry timestamp
    SubscriptionDetails storage details = subscriptionCategories[category];
    uint256 expiryTimestamp = calculateExpiryTimestamp(details.duration);

    // Create a new user and store their information
    uint256 id = _getNextUserID(); // Implement this function to generate unique IDs
    users[msg.sender] = User({
        id: id,
        name: name,
        email: email,
        subscriptionCategory: category,
        payoutAddress: payoutAddress,
        subscriptionExpiry: expiryTimestamp
    });
    }


    modifier onlyAdmin() {
    require(hasRole(msg.sender, "admin"), "Admin access required");
     _;
    }

    modifier onlyOwner() {
    require (msg.sender= "Owner", "Admin access required");
     _;
    }

    // User Unique ID Counter 
    uint256 private _userIdCounter;

    function _getNextUserID() internal onlyAdmin returns (uint256) {
    // Combine user address and timestamp for hashing (optional)
    bytes memory data = abi.encodePacked(msg.sender, block.timestamp);

    // Generate a unique hash using a secure algorithm like keccak256
    bytes32 hash = keccak256(data);

    // Convert the hash to a uint256
    uint256 id = uint256(hash);

    // Check for potential collisions
    require(users[id].id == 0, "ID collision detected. Please retry");

    // Increment the counter and return the new ID
    _userIdCounter++;

    return id;
    }



    /*====== Create New User Subscription Category ==========*/

    function createNewSubscriptionCategory(
    string memory categoryName,
    uint256 durationInDays,
    bool isPaid,
    uint256 termAmount,
    uint256 paymentIntervalInDays,
    uint256 profitPayoutPercentage
    ) external onlyOwner {
    // Create a new subscription category
    SubscriptionCategory newCategory;

    // Set subscription category details
    setSubscriptionCategory(newCategory, categoryName, durationInDays, isPaid, termAmount);

    // Set payment interval
    setPaymentInterval(paymentIntervalInDays);

    // Set profit calculation method (function named setProfitCalculationMethod)
    setProfitCalculationMethod(newCategory, ProfitCalculationMethod);

    // Set profit payout percentage (function named setProfitPayoutPercentage)
    setProfitPayoutPercentage(newCategory, profitPayoutPercentage );
    }

    // Function to set subscription category details
    function setSubscriptionCategory(
    SubscriptionCategory category,
    string memory categoryName,
    uint256 durationInDays,
    bool isPaid,
    uint256 termAmount
    ) external onlyOwner {
    // Set the subscription details
    subscriptionCategories[category] = SubscriptionDetails({
        duration: durationInDays,
        expiryTimestamp: block.timestamp + durationInDays * 1 days,
        isPaid: isPaid,
        termAmount: termAmount
    });

    // You can also store the category name if needed
    // Store the category name
    categoryName[category] = categoryName;
    // categoryName can be used as needed in your logic
    }

    // Function to get subscription details
    function getSubscriptionDetails(SubscriptionCategory category) external view returns (string memory, uint256, uint256, bool, uint256) {
    SubscriptionDetails memory details = subscriptionCategories[category];
    return (categoryName, details.duration, details.expiryTimestamp, details.isPaid, details.termAmount);
    }

    /*
    //improved setSubscriptionCategory version
    function setSubscriptionCategory(
    SubscriptionCategory category,
    string memory categoryName,
    uint256 durationInDays,
    bool isPaid,
    uint256 termAmount,
    uint256 lastPaymentRoundAmount
    ) external onlyOwner {
    // Set the subscription details
    subscriptionCategories[category] = SubscriptionDetails({
        duration: durationInDays,
        expiryTimestamp: block.timestamp + durationInDays * 1 days,
        isPaid: isPaid,
        termAmount: termAmount,
        lastRoundPaymentAmount: lastPaymentRoundAmount // Payout profit percentage + term amount used for percentage calculation
    });

    // Store the category name
    categoryNames[category] = categoryName;
    }
    */

    // Function to set the payment interval in days
    function setPaymentInterval(uint256 intervalInDays) external onlyOwner {
    // Set the day number directly and convert to seconds
    paymentInterval = intervalInDays * 1 days;
    }

    // Function to set the payment interval
    function setPaymentInterval(uint256 intervalInSeconds) external onlyOwner {
        paymentInterval = intervalInSeconds;
    }

    // Function to set the profit payout percentage
    function setProfitPayoutPercentage(uint256 percentage) external onlyOwner {
        require(percentage <= 100, "Percentage must be <= 100");
        profitPayoutPercentage = percentage;
    }

    // Function to set the profit calculation method
    function setProfitCalculationMethod(ProfitCalculationMethod method) external onlyOwner {
        calculationMethod = method;
    }

    // Function to calculate the user's share of profit
    function calculateProfitShare(uint256 termAmount, uint256 dailyProfit) internal view returns (uint256) {
        if (calculationMethod == ProfitCalculationMethod.DailyProfit) {
            return (dailyProfit * profitPayoutPercentage) / 100;
        } else if (calculationMethod == ProfitCalculationMethod.TermAmount) {
            return (termAmount * profitPayoutPercentage) / 100;
        } else {
            revert("Invalid profit calculation method");
        }
    }



}





