// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @dev Interface for mintable ERC20 tokens (matches ERC20 contract from ERC20 folder)
 * The contract must have MINTER_ROLE to call this function
 */
interface IERC20Mintable {
    function mint(address to, uint256 amount) external;
}

/**
 * @title TokenSale
 * @dev Token sale contract where users can pay with specified tokens (or ETH) to receive newly minted base tokens
 */
contract TokenSale is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");

    // Base token being sold (must have mint function)
    address public baseToken;
    
    // Payment recipient (where payments are forwarded)
    address public paymentRecipient;
    
    // Optional whitelist requirement
    bool public requireWhitelist;
    
    // Whitelist management
    mapping(address => bool) public whitelist;
    
    // Payment token configuration
    // paymentToken => tokensPerPayment (how many base tokens per 1 unit of payment token)
    // For ETH, use address(0) as the key
    // Rate is stored as: base tokens (18 decimals) per 1 payment token unit
    // Admin must calculate rate accounting for payment token decimals
    // Example: 1 USDC (6 decimals) = 100 BASE (18 decimals)
    // Rate = 100 * 10^18, calculation: (paymentAmount * rate) / 10^paymentTokenDecimals
    mapping(address => uint256) public paymentTokenRates;
    mapping(address => uint8) public paymentTokenDecimals; // Store decimals for each payment token
    mapping(address => bool) public allowedPaymentTokens;
    
    // Oracle configuration for dynamic pricing
    mapping(address => address) public paymentTokenOracles; // paymentToken => Chainlink oracle address
    mapping(address => bool) public useOracleForToken; // paymentToken => whether to use oracle
    mapping(address => uint256) public oracleStalenessThreshold; // paymentToken => max seconds for price staleness
    uint256 public defaultStalenessThreshold; // Default staleness threshold (24 hours)
    
    // Base rate configuration - all payment rates derive from this
    address public basePaymentToken; // Base payment token address (e.g., EUR token, or address(0) for ETH)
    uint256 public baseRate; // Base tokens per base payment token (18 decimals) - e.g., 1 * 10^18 means 1 token = 1 base payment token
    
    // Sale statistics
    mapping(address => uint256) public totalPurchased; // Total base tokens purchased per user
    mapping(address => mapping(address => uint256)) public purchasedByToken; // User => PaymentToken => Amount purchased
    uint256 public totalSales; // Total base tokens sold
    uint256 public totalRevenue; // Total revenue (in base token units for tracking)
    mapping(address => uint256) public revenueByToken; // PaymentToken => Total revenue in that token
    
    // Order ID tracking (optional, bytes32(0) means no orderId)
    mapping(bytes32 => bool) public usedOrderIds; // Track used order IDs to prevent duplicates
    
    // Sale limits and constraints
    uint256 public hardCap; // Maximum total tokens that can be sold (0 = unlimited)
    uint256 public minPurchaseAmount; // Minimum tokens that must be purchased per transaction (0 = no minimum)
    uint256 public maxPurchasePerUser; // Maximum tokens a single user can purchase (0 = unlimited)
    mapping(address => uint256) public maxPurchasePerUserMapping; // Per-user max purchase override (0 = use global)
    
    // Time-based sale windows
    uint256 public saleStartTime; // Sale start timestamp (0 = no start time restriction)
    uint256 public saleEndTime; // Sale end timestamp (0 = no end time restriction)

    // Events
    event TokensPurchased(
        address indexed buyer,
        address indexed paymentToken,
        uint256 paymentAmount,
        uint256 baseTokensReceived,
        bytes32 orderId
    );
    event PaymentTokenAdded(address indexed token, uint256 rate);
    event PaymentTokenRemoved(address indexed token);
    event PaymentTokenRateUpdated(address indexed token, uint256 newRate);
    event WhitelistAdded(address indexed account);
    event WhitelistRemoved(address indexed account);
    event WhitelistRequirementUpdated(bool requireWhitelist);
    event PaymentRecipientUpdated(address indexed newRecipient);
    event OracleConfigured(address indexed paymentToken, address indexed oracle, uint256 stalenessThreshold);
    event OracleRemoved(address indexed paymentToken);
    event OracleModeUpdated(address indexed paymentToken, bool useOracle);
    event StalenessThresholdUpdated(address indexed paymentToken, uint256 newThreshold);
    event DefaultStalenessThresholdUpdated(uint256 newThreshold);
    event BaseRateConfigured(address indexed basePaymentToken, uint256 baseRate);
    event BaseRateUpdated(uint256 newBaseRate);
    event BasePaymentTokenUpdated(address indexed newBasePaymentToken);
    event HardCapUpdated(uint256 newHardCap);
    event MinPurchaseAmountUpdated(uint256 newMinPurchaseAmount);
    event MaxPurchasePerUserUpdated(uint256 newMaxPurchasePerUser);
    event MaxPurchasePerUserSet(address indexed user, uint256 maxPurchase);
    event SaleTimeWindowUpdated(uint256 startTime, uint256 endTime);
    event SaleConfigured(uint256 hardCap, uint256 minPurchaseAmount, uint256 maxPurchasePerUser, uint256 saleStartTime, uint256 saleEndTime);
    event EmergencyWithdrawal(address indexed token, address indexed recipient, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the TokenSale contract
     * @param _baseToken Address of the base token to sell (must have MINTER_ROLE)
     * @param _paymentRecipient Address that receives payment tokens
     * @param _admin Admin address
     */
    function initialize(
        address _baseToken,
        address _paymentRecipient,
        address _admin
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        require(_baseToken != address(0), "TokenSale: invalid base token");
        require(_paymentRecipient != address(0), "TokenSale: invalid payment recipient");
        require(_admin != address(0), "TokenSale: invalid admin");

        baseToken = _baseToken;
        paymentRecipient = _paymentRecipient;
        requireWhitelist = false; // Whitelist optional by default
        defaultStalenessThreshold = 24 hours; // Default 24 hours staleness threshold
        
        // Initialize sale limits (all 0 = unlimited/no restrictions)
        hardCap = 0; // 0 = unlimited
        minPurchaseAmount = 0; // 0 = no minimum
        maxPurchasePerUser = 0; // 0 = unlimited
        saleStartTime = 0; // 0 = no start time restriction
        saleEndTime = 0; // 0 = no end time restriction

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(WHITELIST_ROLE, _admin);
    }

    // ============ Admin Functions ============

    /**
     * @dev Add a payment token with its rate
     * @param paymentToken Address of the payment token (address(0) for ETH)
     * @param tokensPerPayment How many base tokens (18 decimals) per 1 unit of payment token
     * @param paymentTokenDecimals_ Decimals of the payment token (18 for ETH)
     *                        Example: If 1 USDC (6 decimals) = 100 base tokens (18 decimals)
     *                        Then tokensPerPayment = 100 * 10^18, paymentTokenDecimals_ = 6
     *                        Calculation: (paymentAmount * tokensPerPayment) / 10^paymentTokenDecimals_
     */
    function addPaymentToken(address paymentToken, uint256 tokensPerPayment, uint8 paymentTokenDecimals_) external onlyRole(ADMIN_ROLE) {
        require(tokensPerPayment > 0, "TokenSale: invalid rate");
        require(paymentTokenDecimals_ <= 18, "TokenSale: invalid decimals");
        allowedPaymentTokens[paymentToken] = true;
        paymentTokenRates[paymentToken] = tokensPerPayment;
        paymentTokenDecimals[paymentToken] = paymentTokenDecimals_;
        emit PaymentTokenAdded(paymentToken, tokensPerPayment);
    }

    /**
     * @dev Remove a payment token
     * @param paymentToken Address of the payment token to remove
     */
    function removePaymentToken(address paymentToken) external onlyRole(ADMIN_ROLE) {
        require(allowedPaymentTokens[paymentToken], "TokenSale: token not allowed");
        allowedPaymentTokens[paymentToken] = false;
        paymentTokenRates[paymentToken] = 0;
        emit PaymentTokenRemoved(paymentToken);
    }

    /**
     * @dev Update the rate for a payment token
     * @param paymentToken Address of the payment token
     * @param newRate New rate (base tokens per payment token)
     */
    function updatePaymentTokenRate(address paymentToken, uint256 newRate) external onlyRole(ADMIN_ROLE) {
        require(allowedPaymentTokens[paymentToken], "TokenSale: token not allowed");
        require(newRate > 0, "TokenSale: invalid rate");
        paymentTokenRates[paymentToken] = newRate;
        emit PaymentTokenRateUpdated(paymentToken, newRate);
    }

    /**
     * @dev Add address to whitelist
     * @param account Address to add
     */
    function addToWhitelist(address account) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || hasRole(WHITELIST_ROLE, msg.sender), "TokenSale: must have admin or whitelist role");
        require(account != address(0), "TokenSale: invalid account");
        require(!whitelist[account], "TokenSale: already whitelisted");
        whitelist[account] = true;
        emit WhitelistAdded(account);
    }

    /**
     * @dev Remove address from whitelist
     * @param account Address to remove
     */
    function removeFromWhitelist(address account) external {
        require(hasRole(ADMIN_ROLE, msg.sender) || hasRole(WHITELIST_ROLE, msg.sender), "TokenSale: must have admin or whitelist role");
        require(whitelist[account], "TokenSale: not whitelisted");
        whitelist[account] = false;
        emit WhitelistRemoved(account);
    }

    /**
     * @dev Update whitelist requirement
     * @param _requireWhitelist Whether whitelist is required
     */
    function updateWhitelistRequirement(bool _requireWhitelist) external onlyRole(ADMIN_ROLE) {
        requireWhitelist = _requireWhitelist;
        emit WhitelistRequirementUpdated(_requireWhitelist);
    }

    /**
     * @dev Update payment recipient
     * @param _paymentRecipient New payment recipient address
     */
    function updatePaymentRecipient(address _paymentRecipient) external onlyRole(ADMIN_ROLE) {
        require(_paymentRecipient != address(0), "TokenSale: invalid recipient");
        paymentRecipient = _paymentRecipient;
        emit PaymentRecipientUpdated(_paymentRecipient);
    }


    /**
     * @dev Pause token sales
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause token sales
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ============ Oracle Configuration Functions ============

    /**
     * @dev Configure oracle for a payment token
     * @notice When using oracle mode, rates are derived from baseRate and basePaymentToken
     * @notice Base rate must be set first using setBaseRate()
     * @notice Both payment token and base payment token need oracles (both relative to same quote, e.g., USD)
     * @notice Example setup:
     *         - setBaseRate(EUR token, 1 * 10^18) // 1 token = 1 EUR
     *         - configureOracle(EUR, EUR/USD oracle) // For base payment token
     *         - configureOracle(ETH, ETH/USD oracle) // ETH/USD = 3000, EUR/USD = 1.10
     *         - Result: 1 ETH = 3000/1.10 = 2727.27 tokens
     * @param paymentToken Address of the payment token (address(0) for ETH)
     * @param oracle Address of the Chainlink price feed oracle (e.g., ETH/USD, EUR/USD, BTC/USD)
     * @param stalenessThreshold Maximum seconds before price is considered stale (0 uses default of 24 hours)
     */
    function configureOracle(
        address paymentToken,
        address oracle,
        uint256 stalenessThreshold
    ) external onlyRole(ADMIN_ROLE) {
        require(allowedPaymentTokens[paymentToken], "TokenSale: payment token not allowed");
        require(oracle != address(0), "TokenSale: invalid oracle address");
        
        // Verify oracle is valid by checking it has the required interface
        try AggregatorV3Interface(oracle).decimals() returns (uint8) {
            // Oracle is valid
        } catch {
            revert("TokenSale: invalid oracle interface");
        }

        paymentTokenOracles[paymentToken] = oracle;
        useOracleForToken[paymentToken] = true;
        uint256 threshold = stalenessThreshold > 0 ? stalenessThreshold : defaultStalenessThreshold;
        oracleStalenessThreshold[paymentToken] = threshold;
        
        emit OracleConfigured(paymentToken, oracle, threshold);
    }

    /**
     * @dev Remove oracle configuration for a payment token (falls back to manual rate)
     * @param paymentToken Address of the payment token
     */
    function removeOracle(address paymentToken) external onlyRole(ADMIN_ROLE) {
        require(allowedPaymentTokens[paymentToken], "TokenSale: payment token not allowed");
        useOracleForToken[paymentToken] = false;
        paymentTokenOracles[paymentToken] = address(0);
        emit OracleRemoved(paymentToken);
    }

    /**
     * @dev Enable or disable oracle mode for a payment token
     * @param paymentToken Address of the payment token
     * @param useOracle Whether to use oracle (true) or manual rate (false)
     */
    function setOracleMode(address paymentToken, bool useOracle) external onlyRole(ADMIN_ROLE) {
        require(allowedPaymentTokens[paymentToken], "TokenSale: payment token not allowed");
        if (useOracle) {
            require(paymentTokenOracles[paymentToken] != address(0), "TokenSale: oracle not configured");
        }
        useOracleForToken[paymentToken] = useOracle;
        emit OracleModeUpdated(paymentToken, useOracle);
    }

    /**
     * @dev Update staleness threshold for a payment token
     * @param paymentToken Address of the payment token
     * @param newThreshold New staleness threshold in seconds
     */
    function updateStalenessThreshold(address paymentToken, uint256 newThreshold) external onlyRole(ADMIN_ROLE) {
        require(allowedPaymentTokens[paymentToken], "TokenSale: payment token not allowed");
        require(newThreshold > 0, "TokenSale: invalid threshold");
        oracleStalenessThreshold[paymentToken] = newThreshold;
        emit StalenessThresholdUpdated(paymentToken, newThreshold);
    }

    /**
     * @dev Update default staleness threshold
     * @param newThreshold New default staleness threshold in seconds
     */
    function updateDefaultStalenessThreshold(uint256 newThreshold) external onlyRole(ADMIN_ROLE) {
        require(newThreshold > 0, "TokenSale: invalid threshold");
        defaultStalenessThreshold = newThreshold;
        emit DefaultStalenessThresholdUpdated(newThreshold);
    }

    // ============ Base Rate Configuration ============

    /**
     * @dev Set the base payment token and base rate
     * @notice This is the central rate that all other payment methods derive from
     * @notice Example: basePaymentToken = EUR token address, baseRate = 1 * 10^18 means "1 token = 1 EUR"
     * @notice For the base payment token itself: rate is used directly (no oracle needed)
     * @notice For other payment tokens: rates are derived via oracles (e.g., ETH/EUR)
     * @param _basePaymentToken Address of the base payment token (address(0) for ETH, or token address for EUR/USDC etc.)
     * @param _baseRate Base tokens per base payment token (18 decimals) - e.g., 1 * 10^18 = 1 token per base payment token
     */
    function setBaseRate(address _basePaymentToken, uint256 _baseRate) external onlyRole(ADMIN_ROLE) {
        require(_baseRate > 0, "TokenSale: invalid base rate");
        require(_basePaymentToken != address(0) || allowedPaymentTokens[address(0)], "TokenSale: base payment token not allowed");
        
        // If it's not ETH (address(0)), verify it's an allowed payment token
        if (_basePaymentToken != address(0)) {
            require(allowedPaymentTokens[_basePaymentToken], "TokenSale: base payment token not allowed");
        }

        basePaymentToken = _basePaymentToken;
        baseRate = _baseRate;
        emit BaseRateConfigured(_basePaymentToken, _baseRate);
    }

    /**
     * @dev Update the base rate
     * @param newBaseRate New base rate (base tokens per base payment token, 18 decimals)
     */
    function updateBaseRate(uint256 newBaseRate) external onlyRole(ADMIN_ROLE) {
        require(newBaseRate > 0, "TokenSale: invalid base rate");
        require(baseRate > 0, "TokenSale: base rate not configured yet"); // Check if baseRate was set (implies basePaymentToken is set)
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);
    }

    /**
     * @dev Update the base payment token
     * @param newBasePaymentToken New base payment token address (must be an allowed payment token)
     */
    function updateBasePaymentToken(address newBasePaymentToken) external onlyRole(ADMIN_ROLE) {
        require(newBasePaymentToken != address(0) || allowedPaymentTokens[address(0)], "TokenSale: invalid base payment token");
        
        // If it's not ETH, verify it's an allowed payment token
        if (newBasePaymentToken != address(0)) {
            require(allowedPaymentTokens[newBasePaymentToken], "TokenSale: base payment token not allowed");
        }

        basePaymentToken = newBasePaymentToken;
        emit BasePaymentTokenUpdated(newBasePaymentToken);
    }

    // ============ Sale Limits Configuration ============

    /**
     * @dev Configure all sale parameters in one transaction
     * @param _hardCap Maximum tokens that can be sold (0 = unlimited)
     * @param _minPurchaseAmount Minimum tokens per transaction (0 = no minimum)
     * @param _maxPurchasePerUser Maximum tokens a user can purchase (0 = unlimited)
     * @param _saleStartTime Sale start timestamp (0 = no start restriction)
     * @param _saleEndTime Sale end timestamp (0 = no end restriction)
     */
    function configureSale(
        uint256 _hardCap,
        uint256 _minPurchaseAmount,
        uint256 _maxPurchasePerUser,
        uint256 _saleStartTime,
        uint256 _saleEndTime
    ) external onlyRole(ADMIN_ROLE) {
        // Validate time window if both are set
        if (_saleStartTime > 0 && _saleEndTime > 0) {
            require(_saleStartTime < _saleEndTime, "TokenSale: invalid time window");
        }

        hardCap = _hardCap;
        minPurchaseAmount = _minPurchaseAmount;
        maxPurchasePerUser = _maxPurchasePerUser;
        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;

        emit SaleConfigured(_hardCap, _minPurchaseAmount, _maxPurchasePerUser, _saleStartTime, _saleEndTime);
    }

    /**
     * @dev Set the hard cap (maximum tokens that can be sold)
     * @param _hardCap Maximum tokens to sell (0 = unlimited)
     */
    function setHardCap(uint256 _hardCap) external onlyRole(ADMIN_ROLE) {
        hardCap = _hardCap;
        emit HardCapUpdated(_hardCap);
    }

    /**
     * @dev Set the minimum purchase amount per transaction
     * @param _minPurchaseAmount Minimum tokens per transaction (0 = no minimum)
     */
    function setMinPurchaseAmount(uint256 _minPurchaseAmount) external onlyRole(ADMIN_ROLE) {
        minPurchaseAmount = _minPurchaseAmount;
        emit MinPurchaseAmountUpdated(_minPurchaseAmount);
    }

    /**
     * @dev Set the maximum purchase per user (global limit)
     * @param _maxPurchasePerUser Maximum tokens a user can purchase (0 = unlimited)
     */
    function setMaxPurchasePerUser(uint256 _maxPurchasePerUser) external onlyRole(ADMIN_ROLE) {
        maxPurchasePerUser = _maxPurchasePerUser;
        emit MaxPurchasePerUserUpdated(_maxPurchasePerUser);
    }

    /**
     * @dev Set the maximum purchase for a specific user (override global limit)
     * @param user Address of the user
     * @param _maxPurchase Maximum tokens this user can purchase (0 = use global limit)
     */
    function setMaxPurchaseForUser(address user, uint256 _maxPurchase) external onlyRole(ADMIN_ROLE) {
        require(user != address(0), "TokenSale: invalid user");
        maxPurchasePerUserMapping[user] = _maxPurchase;
        emit MaxPurchasePerUserSet(user, _maxPurchase);
    }

    /**
     * @dev Set the sale time window
     * @param _saleStartTime Sale start timestamp (0 = no start restriction)
     * @param _saleEndTime Sale end timestamp (0 = no end restriction)
     */
    function setSaleTimeWindow(uint256 _saleStartTime, uint256 _saleEndTime) external onlyRole(ADMIN_ROLE) {
        if (_saleStartTime > 0 && _saleEndTime > 0) {
            require(_saleStartTime < _saleEndTime, "TokenSale: invalid time window");
        }
        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;
        emit SaleTimeWindowUpdated(_saleStartTime, _saleEndTime);
    }

    /**
     * @dev Emergency withdrawal function to recover tokens/ETH
     * @param token Address of the token to withdraw (address(0) for ETH)
     * @param recipient Address to receive the tokens
     * @param amount Amount to withdraw (0 = withdraw all for this token)
     */
    function emergencyWithdraw(address token, address recipient, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(recipient != address(0), "TokenSale: invalid recipient");
        
        if (token == address(0)) {
            // Withdraw ETH
            uint256 balance = address(this).balance;
            uint256 withdrawAmount = amount == 0 ? balance : amount;
            require(withdrawAmount > 0, "TokenSale: no ETH to withdraw");
            require(withdrawAmount <= balance, "TokenSale: insufficient ETH balance");
            
            (bool sent, ) = recipient.call{value: withdrawAmount}("");
            require(sent, "TokenSale: ETH withdrawal failed");
            emit EmergencyWithdrawal(address(0), recipient, withdrawAmount);
        } else {
            // Withdraw ERC20 token
            uint256 balance = IERC20(token).balanceOf(address(this));
            uint256 withdrawAmount = amount == 0 ? balance : amount;
            require(withdrawAmount > 0, "TokenSale: no tokens to withdraw");
            require(withdrawAmount <= balance, "TokenSale: insufficient token balance");
            
            IERC20(token).safeTransfer(recipient, withdrawAmount);
            emit EmergencyWithdrawal(token, recipient, withdrawAmount);
        }
    }

    // ============ Internal Oracle Functions ============

    /**
     * @dev Get the current rate for a payment token (from base rate, oracle, or manual rate)
     * @param paymentToken Address of the payment token (address(0) for ETH)
     * @return rate Rate in base tokens (18 decimals) per 1 unit of payment token
     * @return decimals Decimals of the payment token
     */
    function getRate(address paymentToken) internal view returns (uint256 rate, uint8 decimals) {
        decimals = paymentTokenDecimals[paymentToken];
        
        // If this is the base payment token, use base rate directly (no oracle needed)
        if (paymentToken == basePaymentToken && baseRate > 0) {
            rate = baseRate;
            return (rate, decimals);
        }
        
        // Check if oracle should be used for this payment token
        if (useOracleForToken[paymentToken] && paymentTokenOracles[paymentToken] != address(0)) {
            try this._getOracleRateInternal(paymentToken) returns (uint256 oracleRate) {
                // Oracle succeeded, use oracle rate
                rate = oracleRate;
                return (rate, decimals);
            } catch {
                // Oracle failed, fall back to manual rate
                rate = paymentTokenRates[paymentToken];
                return (rate, decimals);
            }
        }
        
        // Use manual rate (if set)
        rate = paymentTokenRates[paymentToken];
        return (rate, decimals);
    }

    /**
     * @dev Get rate from Chainlink oracle with staleness check (internal via external for try-catch)
     * @notice Derives rate from base rate and base payment token
     * @notice Requires oracles for both paymentToken and basePaymentToken (both relative to USD or same quote currency)
     * @notice Formula: rate = baseRate * (paymentTokenPrice / basePaymentTokenPrice)
     * @notice Example: basePaymentToken = EUR, baseRate = 1 * 10^18 (1 token = 1 EUR)
     * @notice If ETH/USD = 3000 and EUR/USD = 1.10, then 1 ETH = 3000/1.10 = 2727.27 EUR
     * @notice Result: rate = 1 * 10^18 * (3000 / 1.10) = 2727.27 * 10^18 tokens per ETH
     * @param paymentToken Address of the payment token
     * @return rate Rate in base tokens (18 decimals) per 1 unit of payment token
     */
    function _getOracleRateInternal(address paymentToken) external view returns (uint256 rate) {
        // Validate base rate configuration
        require(baseRate > 0, "TokenSale: base rate not set");
        // Note: basePaymentToken can be address(0) for ETH, which is valid
        
        // Get payment token oracle
        address paymentTokenOracle = paymentTokenOracles[paymentToken];
        require(paymentTokenOracle != address(0), "TokenSale: payment token oracle not configured");
        
        // Get base payment token oracle (required to convert paymentToken to basePaymentToken)
        address basePaymentTokenOracle = paymentTokenOracles[basePaymentToken];
        require(basePaymentTokenOracle != address(0), "TokenSale: base payment token oracle not configured");
        
        // Get payment token price (e.g., ETH/USD)
        AggregatorV3Interface paymentTokenPriceFeed = AggregatorV3Interface(paymentTokenOracle);
        (, int256 paymentTokenPrice, , uint256 paymentUpdatedAt, ) = paymentTokenPriceFeed.latestRoundData();
        
        // Validate payment token price data
        require(paymentTokenPrice > 0, "TokenSale: invalid payment token price");
        require(paymentUpdatedAt > 0, "TokenSale: payment token price not updated");
        
        // Get base payment token price (e.g., EUR/USD)
        AggregatorV3Interface basePaymentTokenPriceFeed = AggregatorV3Interface(basePaymentTokenOracle);
        (, int256 basePaymentTokenPrice, , uint256 baseUpdatedAt, ) = basePaymentTokenPriceFeed.latestRoundData();
        
        // Validate base payment token price data
        require(basePaymentTokenPrice > 0, "TokenSale: invalid base payment token price");
        require(baseUpdatedAt > 0, "TokenSale: base payment token price not updated");
        
        // Check staleness for both oracles
        uint256 stalenessThreshold = oracleStalenessThreshold[paymentToken];
        if (stalenessThreshold == 0) stalenessThreshold = defaultStalenessThreshold;
        require(block.timestamp - paymentUpdatedAt <= stalenessThreshold, "TokenSale: payment token price too stale");
        require(block.timestamp - baseUpdatedAt <= stalenessThreshold, "TokenSale: base payment token price too stale");
        
        // Get decimals and normalize prices to 18 decimals
        uint8 paymentTokenOracleDecimals = paymentTokenPriceFeed.decimals();
        uint8 basePaymentTokenOracleDecimals = basePaymentTokenPriceFeed.decimals();
        
        // Normalize both prices to 18 decimals
        uint256 normalizedPaymentPrice = uint256(paymentTokenPrice);
        if (paymentTokenOracleDecimals < 18) {
            normalizedPaymentPrice *= (10 ** (18 - paymentTokenOracleDecimals));
        } else if (paymentTokenOracleDecimals > 18) {
            normalizedPaymentPrice /= (10 ** (paymentTokenOracleDecimals - 18));
        }
        
        uint256 normalizedBasePrice = uint256(basePaymentTokenPrice);
        if (basePaymentTokenOracleDecimals < 18) {
            normalizedBasePrice *= (10 ** (18 - basePaymentTokenOracleDecimals));
        } else if (basePaymentTokenOracleDecimals > 18) {
            normalizedBasePrice /= (10 ** (basePaymentTokenOracleDecimals - 18));
        }
        
        // Calculate rate: baseRate * (paymentTokenPrice / basePaymentTokenPrice)
        // This gives us: tokens per paymentToken = (tokens per basePaymentToken) * (paymentToken / basePaymentToken)
        rate = (baseRate * normalizedPaymentPrice) / normalizedBasePrice;
        
        require(rate > 0, "TokenSale: invalid rate calculation");
        
        return rate;
    }

    // ============ Purchase Functions ============

    /**
     * @dev Purchase tokens with ERC20 payment token
     * @param paymentToken Address of the payment token
     * @param paymentAmount Amount of payment token to pay
     * @param orderId Optional order ID (bytes32(0) means no orderId). If provided, must be unique.
     * @return baseTokensReceived Amount of base tokens received
     */
    function purchaseWithToken(
        address paymentToken,
        uint256 paymentAmount,
        bytes32 orderId
    ) external nonReentrant whenNotPaused returns (uint256 baseTokensReceived) {
        // Check whitelist requirement
        if (requireWhitelist) {
            require(whitelist[msg.sender], "TokenSale: not whitelisted");
        }

        // Validate payment token
        require(allowedPaymentTokens[paymentToken], "TokenSale: payment token not allowed");
        require(paymentToken != address(0), "TokenSale: use purchaseWithETH for ETH");
        require(paymentAmount > 0, "TokenSale: invalid payment amount");

        // Validate sale time window
        if (saleStartTime > 0) {
            require(block.timestamp >= saleStartTime, "TokenSale: sale not started");
        }
        if (saleEndTime > 0) {
            require(block.timestamp <= saleEndTime, "TokenSale: sale ended");
        }

        // Validate orderId (if provided, must not be used before)
        if (orderId != bytes32(0)) {
            require(!usedOrderIds[orderId], "TokenSale: orderId already used");
            usedOrderIds[orderId] = true;
        }

        // Get current rate (from oracle or manual rate)
        (uint256 rate, uint8 decimals) = getRate(paymentToken);
        // Rate is stored as: base tokens (18 decimals) per 1 payment token unit
        // Calculation: (paymentAmount * rate) / 10^decimals
        baseTokensReceived = (paymentAmount * rate) / (10 ** decimals);

        require(baseTokensReceived > 0, "TokenSale: insufficient payment");

        // Validate minimum purchase amount
        if (minPurchaseAmount > 0) {
            require(baseTokensReceived >= minPurchaseAmount, "TokenSale: purchase below minimum");
        }

        // Validate hard cap (check against total supply including pre-minted tokens)
        if (hardCap > 0) {
            require(IERC20(baseToken).totalSupply() + baseTokensReceived <= hardCap, "TokenSale: hard cap exceeded");
        }

        // Validate user purchase limits (check against actual balance including tokens from other sources)
        uint256 userMaxPurchase = maxPurchasePerUserMapping[msg.sender];
        if (userMaxPurchase == 0) {
            userMaxPurchase = maxPurchasePerUser;
        }
        if (userMaxPurchase > 0) {
            require(IERC20(baseToken).balanceOf(msg.sender) + baseTokensReceived <= userMaxPurchase, "TokenSale: user purchase limit exceeded");
        }

        // Transfer payment token from buyer
        IERC20(paymentToken).safeTransferFrom(msg.sender, paymentRecipient, paymentAmount);

        // Mint base tokens to buyer
        // This contract must have MINTER_ROLE on the base token (ERC20 contract)
        // The mint function will check for MINTER_ROLE automatically
        IERC20Mintable(baseToken).mint(msg.sender, baseTokensReceived);

        // Update statistics
        totalPurchased[msg.sender] += baseTokensReceived;
        purchasedByToken[msg.sender][paymentToken] += baseTokensReceived;
        totalSales += baseTokensReceived;
        totalRevenue += paymentAmount;
        revenueByToken[paymentToken] += paymentAmount;

        emit TokensPurchased(msg.sender, paymentToken, paymentAmount, baseTokensReceived, orderId);
    }

    /**
     * @dev Purchase tokens with ETH
     * @param orderId Optional order ID (bytes32(0) means no orderId). If provided, must be unique.
     * @return baseTokensReceived Amount of base tokens received
     */
    function purchaseWithETH(bytes32 orderId) external payable nonReentrant whenNotPaused returns (uint256 baseTokensReceived) {
        // Check whitelist requirement
        if (requireWhitelist) {
            require(whitelist[msg.sender], "TokenSale: not whitelisted");
        }

        // Validate ETH payment
        require(allowedPaymentTokens[address(0)], "TokenSale: ETH not allowed");
        require(msg.value > 0, "TokenSale: invalid payment amount");

        // Validate sale time window
        if (saleStartTime > 0) {
            require(block.timestamp >= saleStartTime, "TokenSale: sale not started");
        }
        if (saleEndTime > 0) {
            require(block.timestamp <= saleEndTime, "TokenSale: sale ended");
        }

        // Validate orderId (if provided, must not be used before)
        if (orderId != bytes32(0)) {
            require(!usedOrderIds[orderId], "TokenSale: orderId already used");
            usedOrderIds[orderId] = true;
        }

        // Get current rate (from oracle or manual rate)
        (uint256 rate, uint8 decimals) = getRate(address(0));
        // Should be 18 for ETH
        baseTokensReceived = (msg.value * rate) / (10 ** decimals);

        require(baseTokensReceived > 0, "TokenSale: insufficient payment");

        // Validate minimum purchase amount
        if (minPurchaseAmount > 0) {
            require(baseTokensReceived >= minPurchaseAmount, "TokenSale: purchase below minimum");
        }

        // Validate hard cap (check against total supply including pre-minted tokens)
        if (hardCap > 0) {
            require(IERC20(baseToken).totalSupply() + baseTokensReceived <= hardCap, "TokenSale: hard cap exceeded");
        }

        // Validate user purchase limits (check against actual balance including tokens from other sources)
        uint256 userMaxPurchase = maxPurchasePerUserMapping[msg.sender];
        if (userMaxPurchase == 0) {
            userMaxPurchase = maxPurchasePerUser;
        }
        if (userMaxPurchase > 0) {
            require(IERC20(baseToken).balanceOf(msg.sender) + baseTokensReceived <= userMaxPurchase, "TokenSale: user purchase limit exceeded");
        }

        // Transfer ETH to payment recipient
        (bool sent, ) = paymentRecipient.call{value: msg.value}("");
        require(sent, "TokenSale: ETH transfer failed");

        // Mint base tokens to buyer
        IERC20Mintable(baseToken).mint(msg.sender, baseTokensReceived);

        // Update statistics
        totalPurchased[msg.sender] += baseTokensReceived;
        purchasedByToken[msg.sender][address(0)] += baseTokensReceived;
        totalSales += baseTokensReceived;
        totalRevenue += msg.value;
        revenueByToken[address(0)] += msg.value;

        emit TokensPurchased(msg.sender, address(0), msg.value, baseTokensReceived, orderId);
    }

    // ============ View Functions ============

    /**
     * @dev Calculate how many base tokens would be received for a payment amount
     * @param paymentToken Address of the payment token (address(0) for ETH)
     * @param paymentAmount Amount of payment token (with its decimals)
     * @return baseTokens Amount of base tokens that would be received (with 18 decimals)
     */
    function calculateTokens(address paymentToken, uint256 paymentAmount) external view returns (uint256 baseTokens) {
        require(allowedPaymentTokens[paymentToken], "TokenSale: payment token not allowed");
        (uint256 rate, uint8 decimals) = getRate(paymentToken);
        baseTokens = (paymentAmount * rate) / (10 ** decimals);
    }

    /**
     * @dev Get purchase statistics for a user
     * @param user Address of the user
     * @return total Total base tokens purchased
     */
    function getUserPurchases(address user) external view returns (uint256 total) {
        return totalPurchased[user];
    }

    /**
     * @dev Get purchase statistics for a user by payment token
     * @param user Address of the user
     * @param paymentToken Address of the payment token
     * @return amount Base tokens purchased using this payment token
     */
    function getUserPurchasesByToken(address user, address paymentToken) external view returns (uint256 amount) {
        return purchasedByToken[user][paymentToken];
    }
}
