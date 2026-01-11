// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {TokenSale} from "../src/TokenSale.sol";
import {Upgrades} from "@openzeppelin-foundry-upgrades/Upgrades.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockERC20 is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}

contract MockChainlinkOracle is AggregatorV3Interface {
    uint8 public override decimals;
    string public override description;
    uint256 public override version;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId;

    constructor(uint8 _decimals, int256 _initialAnswer, string memory _description) {
        decimals = _decimals;
        answer = _initialAnswer;
        updatedAt = block.timestamp;
        roundId = 1;
        version = 1;
        description = _description;
    }

    function updateAnswer(int256 _answer) external {
        answer = _answer;
        updatedAt = block.timestamp;
        roundId++;
    }

    function getRoundData(uint80 _roundId) external view override returns (
        uint80,
        int256,
        uint256,
        uint256,
        uint80
    ) {
        return (roundId, answer, updatedAt, updatedAt, roundId);
    }

    function latestRoundData() external view override returns (
        uint80,
        int256,
        uint256,
        uint256,
        uint80
    ) {
        return (roundId, answer, updatedAt, updatedAt, roundId);
    }
}

contract TokenSaleTest is Test {
    TokenSale public tokenSale;
    MockERC20 public baseToken;
    MockERC20 public usdc;
    address public admin;
    address public paymentRecipient;
    address public user1;
    address public user2;

    function setUp() public {
        admin = address(this);
        paymentRecipient = address(0x123);
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy mock tokens
        baseToken = new MockERC20("Base Token", "BASE");
        usdc = new MockERC20("USD Coin", "USDC");

        // Deploy TokenSale contract with proxy
        address proxyAddress = Upgrades.deployTransparentProxy(
            "TokenSale.sol:TokenSale",
            admin,
            abi.encodeCall(
                TokenSale.initialize,
                (address(baseToken), paymentRecipient, admin)
            )
        );

        tokenSale = TokenSale(proxyAddress);

        // Grant MINTER_ROLE to TokenSale contract on base token
        // This allows TokenSale to mint tokens directly
        bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
        baseToken.grantRole(MINTER_ROLE, address(tokenSale));

        // Setup: mint payment tokens to users
        usdc.mint(user1, 100000 * 10 ** usdc.decimals());
        usdc.mint(user2, 100000 * 10 ** usdc.decimals());

        // Add payment tokens
        // Rate: 1 USDC (6 decimals) = 100 BASE tokens (18 decimals)
        // Rate = 100 * 10^18 (base tokens per 1 USDC unit)
        // Calculation: (paymentAmount * rate) / 10^6
        uint256 usdcRate = 100 * 10 ** 18; // 100 base tokens per 1 USDC
        vm.prank(admin);
        tokenSale.addPaymentToken(address(usdc), usdcRate, 6);

        // Add ETH as payment token
        // Rate: 1 ETH = 1000 BASE tokens
        // Rate = 1000 * 10^18 (base tokens per 1 ETH)
        // Calculation: (paymentAmount * rate) / 10^18
        uint256 ethRate = 1000 * 10 ** 18; // 1000 base tokens per 1 ETH
        vm.prank(admin);
        tokenSale.addPaymentToken(address(0), ethRate, 18);
    }

    function test_Initialization() public {
        assertEq(address(tokenSale.baseToken()), address(baseToken));
        assertEq(tokenSale.paymentRecipient(), paymentRecipient);
        assertFalse(tokenSale.requireWhitelist());
    }

    function test_PurchaseWithToken() public {
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals(); // 1000 USDC
        uint256 expectedTokens = tokenSale.calculateTokens(address(usdc), paymentAmount);

        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        uint256 tokensReceived = tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        assertEq(tokensReceived, expectedTokens);
        assertEq(baseToken.balanceOf(user1), tokensReceived);
        assertEq(usdc.balanceOf(paymentRecipient), paymentAmount);
        assertEq(tokenSale.totalPurchased(user1), tokensReceived);
    }

    function test_PurchaseWithETH() public {
        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = tokenSale.calculateTokens(address(0), ethAmount);

        vm.deal(user1, ethAmount);
        vm.startPrank(user1);
        uint256 tokensReceived = tokenSale.purchaseWithETH{value: ethAmount}(bytes32(0));
        vm.stopPrank();

        assertEq(tokensReceived, expectedTokens);
        assertEq(baseToken.balanceOf(user1), tokensReceived);
        assertEq(paymentRecipient.balance, ethAmount);
        assertEq(tokenSale.totalPurchased(user1), tokensReceived);
    }

    function test_WhitelistRequirement() public {
        // Enable whitelist
        vm.prank(admin);
        tokenSale.updateWhitelistRequirement(true);

        // Try to purchase without whitelist (should fail)
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        vm.expectRevert("TokenSale: not whitelisted");
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        // Add to whitelist
        vm.prank(admin);
        tokenSale.addToWhitelist(user1);

        // Now should work
        vm.startPrank(user1);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();
    }

    function test_UpdatePaymentTokenRate() public {
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        uint256 oldRate = tokenSale.paymentTokenRates(address(usdc));
        
        // Update rate to double
        uint256 newRate = oldRate * 2;
        vm.prank(admin);
        tokenSale.updatePaymentTokenRate(address(usdc), newRate);

        uint256 expectedTokens = tokenSale.calculateTokens(address(usdc), paymentAmount);
        // Use payment token decimals (6 for USDC), not 18
        uint8 paymentDecimals = tokenSale.paymentTokenDecimals(address(usdc));
        assertEq(expectedTokens, (paymentAmount * newRate) / (10 ** paymentDecimals));
    }

    function test_RemovePaymentToken() public {
        vm.prank(admin);
        tokenSale.removePaymentToken(address(usdc));

        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        vm.expectRevert("TokenSale: payment token not allowed");
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();
    }

    function test_PauseUnpause() public {
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();

        // Pause
        vm.prank(admin);
        tokenSale.pause();

        // Try to purchase (should fail)
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        vm.expectRevert();
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        // Unpause
        vm.prank(admin);
        tokenSale.unpause();

        // Now should work
        vm.startPrank(user1);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();
    }

    function test_Statistics() public {
        uint256 paymentAmount1 = 1000 * 10 ** usdc.decimals();
        uint256 paymentAmount2 = 2 ether;

        // Purchase with USDC
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount1);
        uint256 tokens1 = tokenSale.purchaseWithToken(address(usdc), paymentAmount1, bytes32(0));
        vm.stopPrank();

        // Purchase with ETH
        vm.deal(user2, paymentAmount2);
        vm.startPrank(user2);
        uint256 tokens2 = tokenSale.purchaseWithETH{value: paymentAmount2}(bytes32(0));
        vm.stopPrank();

        // Check statistics
        assertEq(tokenSale.totalPurchased(user1), tokens1);
        assertEq(tokenSale.totalPurchased(user2), tokens2);
        assertEq(tokenSale.totalSales(), tokens1 + tokens2);
        assertEq(tokenSale.purchasedByToken(user1, address(usdc)), tokens1);
        assertEq(tokenSale.purchasedByToken(user2, address(0)), tokens2);
    }

    // ============ Base Rate Tests ============

    function test_SetBaseRate() public {
        // Set USDC as base payment token with rate 1 token = 1 USDC
        uint256 baseRate = 1 * 10 ** 18; // 1 token per 1 USDC
        
        vm.prank(admin);
        tokenSale.setBaseRate(address(usdc), baseRate);

        assertEq(tokenSale.basePaymentToken(), address(usdc));
        assertEq(tokenSale.baseRate(), baseRate);
    }

    function test_SetBaseRateWithETH() public {
        // Set ETH as base payment token with rate 1 token = 0.001 ETH
        uint256 baseRate = 1 * 10 ** 15; // 0.001 tokens per 1 ETH
        
        vm.prank(admin);
        tokenSale.setBaseRate(address(0), baseRate);

        assertEq(tokenSale.basePaymentToken(), address(0));
        assertEq(tokenSale.baseRate(), baseRate);
    }

    function test_UpdateBaseRate() public {
        // Set initial base rate
        uint256 initialRate = 1 * 10 ** 18;
        vm.prank(admin);
        tokenSale.setBaseRate(address(usdc), initialRate);

        // Update base rate
        uint256 newRate = 2 * 10 ** 18;
        vm.prank(admin);
        tokenSale.updateBaseRate(newRate);

        assertEq(tokenSale.baseRate(), newRate);
    }

    function test_UpdateBasePaymentToken() public {
        // Set initial base payment token
        vm.prank(admin);
        tokenSale.setBaseRate(address(usdc), 1 * 10 ** 18);

        // Update to ETH
        vm.prank(admin);
        tokenSale.updateBasePaymentToken(address(0));

        assertEq(tokenSale.basePaymentToken(), address(0));
    }

    function test_PurchaseWithBasePaymentToken() public {
        // Set USDC as base payment token: 1 token = 1 USDC
        uint256 baseRate = 1 * 10 ** 18;
        
        // USDC is already added as payment token in setUp, so we can set it as base
        vm.prank(admin);
        tokenSale.setBaseRate(address(usdc), baseRate);

        // Purchase with base payment token (should use baseRate directly)
        // Use the decimals from the tokenSale mapping (6), not from the token itself (18)
        uint8 usdcDecimals = tokenSale.paymentTokenDecimals(address(usdc));
        uint256 paymentAmount = 1000 * 10 ** usdcDecimals; // 1000 USDC (using 6 decimals)
        // When basePaymentToken is used, getRate returns baseRate directly
        // Then in purchase: tokens = (paymentAmount * baseRate) / 10^decimals
        // tokens = (1000 * 10^6 * 1 * 10^18) / 10^6 = 1000 * 10^18
        uint256 expectedTokens = 1000 * 10 ** 18; // 1000 tokens
        
        // Verify calculation
        uint256 calculated = tokenSale.calculateTokens(address(usdc), paymentAmount);
        assertEq(calculated, expectedTokens);

        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        uint256 tokensReceived = tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        assertEq(tokensReceived, expectedTokens);
        assertEq(baseToken.balanceOf(user1), expectedTokens);
    }

    // ============ Oracle Tests ============

    function test_OracleBasedPricing() public {
        MockERC20 eur = new MockERC20("Euro", "EUR");
        MockChainlinkOracle ethUsdOracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        MockChainlinkOracle eurUsdOracle = new MockChainlinkOracle(8, 110000000, "EUR/USD"); // 1.10 USD per EUR (1.10 * 10^8)

        // Setup: mint EUR to users
        eur.mint(user1, 100000 * 10 ** eur.decimals());

        // Add EUR as payment token FIRST (required before setting as base)
        uint256 baseRate = 1 * 10 ** 18;
        vm.prank(admin);
        tokenSale.addPaymentToken(address(eur), baseRate, 18);

        // Set EUR as base payment token: 1 token = 1 EUR
        vm.prank(admin);
        tokenSale.setBaseRate(address(eur), baseRate);

        // Add ETH as payment token
        vm.prank(admin);
        tokenSale.addPaymentToken(address(0), 1000 * 10 ** 18, 18); // Manual rate as fallback

        // Configure oracles
        vm.prank(admin);
        tokenSale.configureOracle(address(eur), address(eurUsdOracle), 3600); // EUR/USD oracle

        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(ethUsdOracle), 3600); // ETH/USD oracle

        // Calculate expected rate:
        // ETH/USD = 3000, EUR/USD = 1.10
        // ETH/EUR = 3000 / 1.10 = 2727.27...
        // Rate = baseRate * (ETH/EUR) = 1 * 10^18 * 2727.27... = 2727.27... * 10^18
        uint256 ethPrice = 3000 * 10 ** 8; // ETH/USD with 8 decimals
        uint256 eurPrice = 110000000;      // EUR/USD with 8 decimals (1.10 * 10^8)
        
        // Normalize both to 18 decimals, then calculate: baseRate * (ethPrice / eurPrice)
        uint256 normalizedEthPrice = ethPrice * 10 ** 10; // 18 decimals
        uint256 normalizedEurPrice = eurPrice * 10 ** 10; // 18 decimals
        uint256 expectedRate = (baseRate * normalizedEthPrice) / normalizedEurPrice;
        
        // Purchase with ETH
        uint256 ethAmount = 1 ether;
        vm.deal(user1, ethAmount);
        
        vm.startPrank(user1);
        uint256 tokensReceived = tokenSale.purchaseWithETH{value: ethAmount}(bytes32(0));
        vm.stopPrank();

        // Expected: 1 ETH = 2727.27... tokens (approximately)
        uint256 expectedTokens = (ethAmount * expectedRate) / (10 ** 18);
        assertApproxEqRel(tokensReceived, expectedTokens, 0.01e18); // 1% tolerance for rounding
    }

    function test_OracleFallbackToManualRate() public {
        MockChainlinkOracle failingOracle = new MockChainlinkOracle(8, -1, "FAILING/USD"); // Negative price will fail

        // Add ETH with manual rate
        vm.prank(admin);
        tokenSale.addPaymentToken(address(0), 1000 * 10 ** 18, 18);

        // Configure oracle (but it will fail)
        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(failingOracle), 3600);

        // Purchase should fallback to manual rate
        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = (ethAmount * 1000 * 10 ** 18) / (10 ** 18); // Manual rate

        vm.deal(user1, ethAmount);
        vm.startPrank(user1);
        uint256 tokensReceived = tokenSale.purchaseWithETH{value: ethAmount}(bytes32(0));
        vm.stopPrank();

        assertEq(tokensReceived, expectedTokens); // Should use manual rate
    }

    function test_OracleStalenessCheck() public {
        MockChainlinkOracle staleOracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        
        // Make oracle stale by setting old timestamp
        vm.warp(block.timestamp + 86401); // 25 hours later
        
        // Set base rate
        MockERC20 eur = new MockERC20("Euro", "EUR");
        uint256 baseRate = 1 * 10 ** 18;
        
        // Add EUR as payment token FIRST
        vm.prank(admin);
        tokenSale.addPaymentToken(address(eur), baseRate, 18);
        
        vm.prank(admin);
        tokenSale.setBaseRate(address(eur), baseRate);
        
        vm.prank(admin);
        tokenSale.addPaymentToken(address(0), 1000 * 10 ** 18, 18);
        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(staleOracle), 3600); // 1 hour threshold

        // Should fallback to manual rate due to staleness
        uint256 ethAmount = 1 ether;
        vm.deal(user1, ethAmount);
        
        vm.startPrank(user1);
        uint256 tokensReceived = tokenSale.purchaseWithETH{value: ethAmount}(bytes32(0));
        vm.stopPrank();

        // Should use manual rate (1000 tokens per ETH)
        assertEq(tokensReceived, 1000 * 10 ** 18);
    }

    // ============ Whitelist Role Tests ============

    function test_WhitelistRoleCanAddToWhitelist() public {
        address whitelistAdmin = address(0x999);
        
        // Grant WHITELIST_ROLE
        bytes32 WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
        vm.prank(admin);
        tokenSale.grantRole(WHITELIST_ROLE, whitelistAdmin);

        // Enable whitelist
        vm.prank(admin);
        tokenSale.updateWhitelistRequirement(true);

        // Whitelist admin should be able to add users
        vm.prank(whitelistAdmin);
        tokenSale.addToWhitelist(user1);

        assertTrue(tokenSale.whitelist(user1));
    }

    function test_WhitelistRoleCanRemoveFromWhitelist() public {
        address whitelistAdmin = address(0x999);
        
        // Grant WHITELIST_ROLE
        bytes32 WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
        vm.prank(admin);
        tokenSale.grantRole(WHITELIST_ROLE, whitelistAdmin);

        // Add user to whitelist
        vm.prank(admin);
        tokenSale.addToWhitelist(user1);

        // Whitelist admin should be able to remove users
        vm.prank(whitelistAdmin);
        tokenSale.removeFromWhitelist(user1);

        assertFalse(tokenSale.whitelist(user1));
    }

    function test_NonAdminCannotSetBaseRate() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.setBaseRate(address(usdc), 1 * 10 ** 18);
    }

    function test_NonAdminCannotConfigureOracle() public {
        MockChainlinkOracle oracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.configureOracle(address(0), address(oracle), 3600);
    }

    function test_NonAdminCannotAddPaymentToken() public {
        MockERC20 token = new MockERC20("Test Token", "TEST");
        
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.addPaymentToken(address(token), 100 * 10 ** 18, 18);
    }

    function test_NonAdminCannotRemovePaymentToken() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.removePaymentToken(address(usdc));
    }

    function test_NonAdminCannotUpdatePaymentTokenRate() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.updatePaymentTokenRate(address(usdc), 200 * 10 ** 18);
    }

    function test_NonAdminCannotUpdateWhitelistRequirement() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.updateWhitelistRequirement(true);
    }

    function test_NonAdminCannotUpdatePaymentRecipient() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.updatePaymentRecipient(address(0x999));
    }

    function test_NonAdminCannotPause() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.pause();
    }

    function test_NonAdminCannotUnpause() public {
        vm.prank(admin);
        tokenSale.pause();
        
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.unpause();
        
        // Clean up - unpause as admin
        vm.prank(admin);
        tokenSale.unpause();
    }

    function test_NonAdminCannotRemoveOracle() public {
        MockChainlinkOracle oracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(oracle), 3600);
        
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.removeOracle(address(0));
    }

    function test_NonAdminCannotSetOracleMode() public {
        MockChainlinkOracle oracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(oracle), 3600);
        
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.setOracleMode(address(0), false);
    }

    function test_NonAdminCannotUpdateStalenessThreshold() public {
        MockChainlinkOracle oracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(oracle), 3600);
        
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.updateStalenessThreshold(address(0), 7200);
    }

    function test_NonAdminCannotUpdateDefaultStalenessThreshold() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.updateDefaultStalenessThreshold(12 hours);
    }

    function test_NonAdminCannotUpdateBaseRate() public {
        vm.prank(admin);
        tokenSale.setBaseRate(address(usdc), 1 * 10 ** 18);
        
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.updateBaseRate(2 * 10 ** 18);
    }

    function test_NonAdminCannotUpdateBasePaymentToken() public {
        vm.prank(admin);
        tokenSale.setBaseRate(address(usdc), 1 * 10 ** 18);
        
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.updateBasePaymentToken(address(0));
    }

    function test_NonAdminCannotConfigureSale() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.configureSale(10000 * 10 ** 18, 100 * 10 ** 18, 5000 * 10 ** 18, block.timestamp + 1 days, block.timestamp + 7 days);
    }

    function test_NonAdminCannotSetHardCap() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.setHardCap(10000 * 10 ** 18);
    }

    function test_NonAdminCannotSetMinPurchaseAmount() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.setMinPurchaseAmount(100 * 10 ** 18);
    }

    function test_NonAdminCannotSetMaxPurchasePerUser() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.setMaxPurchasePerUser(5000 * 10 ** 18);
    }

    function test_NonAdminCannotSetMaxPurchaseForUser() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.setMaxPurchaseForUser(user1, 2000 * 10 ** 18);
    }

    function test_NonAdminCannotSetSaleTimeWindow() public {
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.setSaleTimeWindow(block.timestamp + 1 days, block.timestamp + 7 days);
    }

    function test_NonAdminCannotEmergencyWithdraw() public {
        vm.deal(address(tokenSale), 1 ether);
        
        vm.prank(user1);
        vm.expectRevert();
        tokenSale.emergencyWithdraw(address(0), user1, 0);
    }

    // ============ OrderId Tests ============

    function test_PurchaseWithOptionalOrderId() public {
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        bytes32 orderId = keccak256("ORDER_123");

        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        uint256 tokensReceived = tokenSale.purchaseWithToken(address(usdc), paymentAmount, orderId);
        vm.stopPrank();

        assertGt(tokensReceived, 0);
        assertTrue(tokenSale.usedOrderIds(orderId));
    }

    function test_PurchaseWithoutOrderId() public {
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();

        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        uint256 tokensReceived = tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        assertGt(tokensReceived, 0);
        // bytes32(0) should not be marked as used
        assertFalse(tokenSale.usedOrderIds(bytes32(0)));
    }

    function test_OrderIdCannotBeUsedTwice() public {
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        bytes32 orderId = keccak256("ORDER_456");

        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, orderId);
        vm.stopPrank();

        // Try to use the same orderId again
        usdc.mint(user2, paymentAmount);
        vm.startPrank(user2);
        usdc.approve(address(tokenSale), paymentAmount);
        vm.expectRevert("TokenSale: orderId already used");
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, orderId);
        vm.stopPrank();
    }

    function test_DifferentOrderIdsCanBeUsed() public {
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        bytes32 orderId1 = keccak256("ORDER_789");
        bytes32 orderId2 = keccak256("ORDER_790");

        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount * 2);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, orderId1);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, orderId2);
        vm.stopPrank();

        assertTrue(tokenSale.usedOrderIds(orderId1));
        assertTrue(tokenSale.usedOrderIds(orderId2));
    }

    function test_PurchaseWithETHAndOrderId() public {
        uint256 ethAmount = 1 ether;
        bytes32 orderId = keccak256("ETH_ORDER_123");

        vm.deal(user1, ethAmount);
        vm.startPrank(user1);
        uint256 tokensReceived = tokenSale.purchaseWithETH{value: ethAmount}(orderId);
        vm.stopPrank();

        assertGt(tokensReceived, 0);
        assertTrue(tokenSale.usedOrderIds(orderId));
    }

    function test_OrderIdCannotBeUsedTwiceWithETH() public {
        uint256 ethAmount = 1 ether;
        bytes32 orderId = keccak256("ETH_ORDER_456");

        vm.deal(user1, ethAmount);
        vm.startPrank(user1);
        tokenSale.purchaseWithETH{value: ethAmount}(orderId);
        vm.stopPrank();

        // Try to use the same orderId again
        vm.deal(user2, ethAmount);
        vm.startPrank(user2);
        vm.expectRevert("TokenSale: orderId already used");
        tokenSale.purchaseWithETH{value: ethAmount}(orderId);
        vm.stopPrank();
    }

    // ============ Sale Limits Tests ============

    function test_HardCap() public {
        // Account for initial supply from MockERC20 constructor (1,000,000 tokens)
        uint256 initialSupply = baseToken.totalSupply();
        uint256 cap = initialSupply + 10000 * 10 ** 18; // Initial supply + 10,000 tokens
        vm.prank(admin);
        tokenSale.setHardCap(cap);

        assertEq(tokenSale.hardCap(), cap);

        // Purchase up to cap
        // Rate: 100 tokens per USDC, so 90 USDC = 9,000 tokens
        // Use TokenSale's stored decimals (6), not MockERC20's decimals (18)
        uint8 usdcDecimals = tokenSale.paymentTokenDecimals(address(usdc));
        uint256 paymentAmount = 90 * 10 ** usdcDecimals;
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        // Try to exceed cap (should fail)
        // 20 USDC = 2,000 tokens, total would exceed cap
        uint256 excessPayment = 20 * 10 ** usdcDecimals;
        vm.startPrank(user2);
        usdc.approve(address(tokenSale), excessPayment);
        vm.expectRevert("TokenSale: hard cap exceeded");
        tokenSale.purchaseWithToken(address(usdc), excessPayment, bytes32(0));
        vm.stopPrank();
    }

    function test_MinPurchaseAmount() public {
        uint256 minPurchase = 100 * 10 ** 18; // 100 tokens minimum
        vm.prank(admin);
        tokenSale.setMinPurchaseAmount(minPurchase);

        assertEq(tokenSale.minPurchaseAmount(), minPurchase);

        // Purchase below minimum (should fail)
        // Rate: 100 tokens per USDC, so 0.5 USDC = 50 tokens < 100 minimum
        // Use TokenSale's stored decimals (6), not MockERC20's decimals (18)
        uint8 usdcDecimals = tokenSale.paymentTokenDecimals(address(usdc));
        uint256 smallPayment = 5 * 10 ** (usdcDecimals - 1); // 0.5 USDC
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), smallPayment);
        vm.expectRevert("TokenSale: purchase below minimum");
        tokenSale.purchaseWithToken(address(usdc), smallPayment, bytes32(0));
        vm.stopPrank();

        // Purchase above minimum (should succeed)
        // 10 USDC = 1,000 tokens > 100 minimum
        uint256 largePayment = 10 * 10 ** usdcDecimals;
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), largePayment);
        tokenSale.purchaseWithToken(address(usdc), largePayment, bytes32(0));
        vm.stopPrank();
    }

    function test_MaxPurchasePerUser() public {
        uint256 maxPurchase = 5000 * 10 ** 18; // 5,000 tokens max per user
        vm.prank(admin);
        tokenSale.setMaxPurchasePerUser(maxPurchase);

        assertEq(tokenSale.maxPurchasePerUser(), maxPurchase);

        // Purchase up to limit
        // Rate: 100 tokens per USDC, so 40 USDC = 4,000 tokens
        // Use TokenSale's stored decimals (6), not MockERC20's decimals (18)
        uint8 usdcDecimals = tokenSale.paymentTokenDecimals(address(usdc));
        uint256 paymentAmount = 40 * 10 ** usdcDecimals;
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount * 2);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        // Try to exceed limit (should fail)
        // 20 USDC = 2,000 tokens, total would be 6,000 tokens > 5,000 limit
        uint256 excessPayment = 20 * 10 ** usdcDecimals;
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), excessPayment);
        vm.expectRevert("TokenSale: user purchase limit exceeded");
        tokenSale.purchaseWithToken(address(usdc), excessPayment, bytes32(0));
        vm.stopPrank();
    }

    function test_MaxPurchasePerUserOverride() public {
        uint256 globalMax = 5000 * 10 ** 18;
        uint256 userMax = 2000 * 10 ** 18;
        
        vm.prank(admin);
        tokenSale.setMaxPurchasePerUser(globalMax);
        
        vm.prank(admin);
        tokenSale.setMaxPurchaseForUser(user1, userMax);

        assertEq(tokenSale.maxPurchasePerUserMapping(user1), userMax);

        // User1 should have lower limit
        // Rate: 100 tokens per USDC, so 25 USDC = 2,500 tokens > 2,000 limit for user1
        // Use TokenSale's stored decimals (6), not MockERC20's decimals (18)
        uint8 usdcDecimals = tokenSale.paymentTokenDecimals(address(usdc));
        uint256 paymentAmount = 25 * 10 ** usdcDecimals;
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        vm.expectRevert("TokenSale: user purchase limit exceeded");
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        // User2 should have global limit (2,500 tokens < 5,000 global limit)
        vm.startPrank(user2);
        usdc.approve(address(tokenSale), paymentAmount);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();
    }

    function test_ConfigureSale() public {
        uint256 cap = 10000 * 10 ** 18;
        uint256 minPurchase = 100 * 10 ** 18;
        uint256 maxPurchase = 5000 * 10 ** 18;
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = block.timestamp + 7 days;

        vm.prank(admin);
        tokenSale.configureSale(cap, minPurchase, maxPurchase, startTime, endTime);

        assertEq(tokenSale.hardCap(), cap);
        assertEq(tokenSale.minPurchaseAmount(), minPurchase);
        assertEq(tokenSale.maxPurchasePerUser(), maxPurchase);
        assertEq(tokenSale.saleStartTime(), startTime);
        assertEq(tokenSale.saleEndTime(), endTime);
    }

    function test_ConfigureSaleWithZeroValues() public {
        // Test that all zero values work (unlimited/no restrictions)
        vm.prank(admin);
        tokenSale.configureSale(0, 0, 0, 0, 0);

        assertEq(tokenSale.hardCap(), 0);
        assertEq(tokenSale.minPurchaseAmount(), 0);
        assertEq(tokenSale.maxPurchasePerUser(), 0);
        assertEq(tokenSale.saleStartTime(), 0);
        assertEq(tokenSale.saleEndTime(), 0);
    }

    function test_ConfigureSaleInvalidTimeWindow() public {
        uint256 startTime = block.timestamp + 7 days;
        uint256 endTime = block.timestamp + 1 days; // End before start

        vm.prank(admin);
        vm.expectRevert("TokenSale: invalid time window");
        tokenSale.configureSale(0, 0, 0, startTime, endTime);
    }

    function test_ConfigureSaleAllLimitsActive() public {
        // Account for initial supply from MockERC20 constructor
        uint256 initialSupply = baseToken.totalSupply();
        uint256 additionalTokens = 10000 * 10 ** 18; // 10,000 tokens
        uint256 cap = initialSupply + additionalTokens;
        uint256 minPurchase = 100 * 10 ** 18; // 100 tokens minimum
        uint256 maxPurchase = 5000 * 10 ** 18; // 5,000 tokens max per user
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = block.timestamp + 7 days;

        // Configure sale with all limits
        vm.prank(admin);
        tokenSale.configureSale(cap, minPurchase, maxPurchase, startTime, endTime);

        // Verify all limits are set
        assertEq(tokenSale.hardCap(), cap);
        assertEq(tokenSale.minPurchaseAmount(), minPurchase);
        assertEq(tokenSale.maxPurchasePerUser(), maxPurchase);
        assertEq(tokenSale.saleStartTime(), startTime);
        assertEq(tokenSale.saleEndTime(), endTime);

        uint8 usdcDecimals = tokenSale.paymentTokenDecimals(address(usdc));
        uint256 rate = tokenSale.paymentTokenRates(address(usdc));

        // Try to purchase before sale starts (should fail)
        uint256 paymentAmount = 10 * 10 ** usdcDecimals; // 10 USDC = 1,000 tokens
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        vm.expectRevert("TokenSale: sale not started");
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        // Move time forward to start
        vm.warp(startTime + 1);

        // Try to purchase below minimum (should fail)
        // 0.5 USDC = 50 tokens < 100 minimum
        uint256 smallPayment = 5 * 10 ** (usdcDecimals - 1); // 0.5 USDC
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), smallPayment);
        vm.expectRevert("TokenSale: purchase below minimum");
        tokenSale.purchaseWithToken(address(usdc), smallPayment, bytes32(0));
        vm.stopPrank();

        // Purchase within all limits (should succeed)
        // 40 USDC = 4,000 tokens (within maxPurchase of 5,000, above minPurchase of 100)
        uint256 validPayment = 40 * 10 ** usdcDecimals;
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), validPayment * 2);
        uint256 tokensReceived = tokenSale.purchaseWithToken(address(usdc), validPayment, bytes32(0));
        vm.stopPrank();

        assertGt(tokensReceived, 0);
        assertEq(tokensReceived, (validPayment * rate) / (10 ** usdcDecimals));

        // Try to exceed user max purchase (should fail)
        // 20 USDC = 2,000 tokens, total would be 6,000 tokens > 5,000 limit
        uint256 excessPayment = 20 * 10 ** usdcDecimals;
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), excessPayment);
        vm.expectRevert("TokenSale: user purchase limit exceeded");
        tokenSale.purchaseWithToken(address(usdc), excessPayment, bytes32(0));
        vm.stopPrank();

        // Move time forward past end
        vm.warp(endTime + 1);

        // Try to purchase after sale ends (should fail)
        vm.startPrank(user2);
        usdc.approve(address(tokenSale), validPayment);
        vm.expectRevert("TokenSale: sale ended");
        tokenSale.purchaseWithToken(address(usdc), validPayment, bytes32(0));
        vm.stopPrank();
    }

    function test_SaleTimeWindow() public {
        uint256 startTime = block.timestamp + 1 days;
        uint256 endTime = block.timestamp + 7 days;
        
        vm.prank(admin);
        tokenSale.setSaleTimeWindow(startTime, endTime);

        assertEq(tokenSale.saleStartTime(), startTime);
        assertEq(tokenSale.saleEndTime(), endTime);

        // Try to purchase before sale starts (should fail)
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        vm.expectRevert("TokenSale: sale not started");
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        // Move time forward to start
        vm.warp(startTime + 1);

        // Now should work
        vm.startPrank(user1);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        // Move time forward past end
        vm.warp(endTime + 1);

        // Try to purchase after sale ends (should fail)
        vm.startPrank(user2);
        usdc.approve(address(tokenSale), paymentAmount);
        vm.expectRevert("TokenSale: sale ended");
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();
    }

    function test_EmergencyWithdraw() public {
        // Send some ETH to contract
        vm.deal(address(tokenSale), 5 ether);

        // Send some tokens to contract
        usdc.mint(address(tokenSale), 1000 * 10 ** usdc.decimals());

        address recipient = address(0x999);
        
        // Withdraw ETH
        uint256 ethBalanceBefore = recipient.balance;
        vm.prank(admin);
        tokenSale.emergencyWithdraw(address(0), recipient, 0); // 0 = withdraw all
        
        assertEq(recipient.balance - ethBalanceBefore, 5 ether);

        // Withdraw tokens
        uint256 tokenBalanceBefore = usdc.balanceOf(recipient);
        vm.prank(admin);
        tokenSale.emergencyWithdraw(address(usdc), recipient, 0); // 0 = withdraw all
        
        assertEq(usdc.balanceOf(recipient) - tokenBalanceBefore, 1000 * 10 ** usdc.decimals());
    }

    function test_RevenueTracking() public {
        uint256 paymentAmount1 = 1000 * 10 ** usdc.decimals();
        uint256 paymentAmount2 = 1 ether;

        // Purchase with USDC
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount1);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount1, bytes32(0));
        vm.stopPrank();

        // Purchase with ETH
        vm.deal(user2, paymentAmount2);
        vm.startPrank(user2);
        tokenSale.purchaseWithETH{value: paymentAmount2}(bytes32(0));
        vm.stopPrank();

        // Check revenue by token
        assertEq(tokenSale.revenueByToken(address(usdc)), paymentAmount1);
        assertEq(tokenSale.revenueByToken(address(0)), paymentAmount2);
    }

    // ============ Missing Function Tests ============

    function test_UpdatePaymentRecipient() public {
        address newRecipient = address(0x888);
        
        vm.prank(admin);
        tokenSale.updatePaymentRecipient(newRecipient);

        assertEq(tokenSale.paymentRecipient(), newRecipient);

        // Verify payments go to new recipient
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        assertEq(usdc.balanceOf(newRecipient), paymentAmount);
    }

    function test_RemoveOracle() public {
        MockChainlinkOracle oracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        
        // Configure oracle first
        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(oracle), 3600);
        
        assertTrue(tokenSale.useOracleForToken(address(0)));
        assertEq(tokenSale.paymentTokenOracles(address(0)), address(oracle));

        // Remove oracle
        vm.prank(admin);
        tokenSale.removeOracle(address(0));

        assertFalse(tokenSale.useOracleForToken(address(0)));
        assertEq(tokenSale.paymentTokenOracles(address(0)), address(0));
    }

    function test_SetOracleMode() public {
        MockChainlinkOracle oracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        
        // Configure oracle first
        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(oracle), 3600);
        
        assertTrue(tokenSale.useOracleForToken(address(0)));

        // Disable oracle mode
        vm.prank(admin);
        tokenSale.setOracleMode(address(0), false);
        assertFalse(tokenSale.useOracleForToken(address(0)));

        // Re-enable oracle mode
        vm.prank(admin);
        tokenSale.setOracleMode(address(0), true);
        assertTrue(tokenSale.useOracleForToken(address(0)));
    }

    function test_SetOracleModeWithoutOracle() public {
        // Try to enable oracle mode without configuring oracle (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: oracle not configured");
        tokenSale.setOracleMode(address(0), true);
    }

    function test_UpdateStalenessThreshold() public {
        MockChainlinkOracle oracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        
        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(oracle), 3600);
        
        uint256 newThreshold = 7200; // 2 hours
        vm.prank(admin);
        tokenSale.updateStalenessThreshold(address(0), newThreshold);

        assertEq(tokenSale.oracleStalenessThreshold(address(0)), newThreshold);
    }

    function test_UpdateDefaultStalenessThreshold() public {
        uint256 newThreshold = 12 hours;
        
        vm.prank(admin);
        tokenSale.updateDefaultStalenessThreshold(newThreshold);

        assertEq(tokenSale.defaultStalenessThreshold(), newThreshold);
    }

    function test_CalculateTokens() public {
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        
        uint256 calculated = tokenSale.calculateTokens(address(usdc), paymentAmount);
        uint256 expected = (paymentAmount * tokenSale.paymentTokenRates(address(usdc))) / (10 ** tokenSale.paymentTokenDecimals(address(usdc)));
        
        assertEq(calculated, expected);
    }

    function test_GetUserPurchases() public {
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        uint256 tokensReceived = tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        assertEq(tokenSale.getUserPurchases(user1), tokensReceived);
        assertEq(tokenSale.getUserPurchases(user1), tokenSale.totalPurchased(user1));
    }

    function test_GetUserPurchasesByToken() public {
        uint256 paymentAmount = 1000 * 10 ** usdc.decimals();
        
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount);
        uint256 tokensReceived = tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        assertEq(tokenSale.getUserPurchasesByToken(user1, address(usdc)), tokensReceived);
        assertEq(tokenSale.getUserPurchasesByToken(user1, address(usdc)), tokenSale.purchasedByToken(user1, address(usdc)));
    }

    // ============ Error Case Tests ============

    function test_AddToWhitelistWhenAlreadyWhitelisted() public {
        vm.prank(admin);
        tokenSale.addToWhitelist(user1);

        // Try to add again (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: already whitelisted");
        tokenSale.addToWhitelist(user1);
    }

    function test_RemoveFromWhitelistWhenNotWhitelisted() public {
        // Try to remove when not whitelisted (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: not whitelisted");
        tokenSale.removeFromWhitelist(user1);
    }

    function test_UpdateBaseRateWhenNotConfigured() public {
        // Try to update base rate when not set (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: base rate not configured yet");
        tokenSale.updateBaseRate(1 * 10 ** 18);
    }

    function test_UpdatePaymentRecipientInvalid() public {
        // Try to set invalid recipient (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: invalid recipient");
        tokenSale.updatePaymentRecipient(address(0));
    }

    function test_AddPaymentTokenInvalidRate() public {
        MockERC20 token = new MockERC20("Test Token", "TEST");
        
        // Try to add payment token with zero rate (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: invalid rate");
        tokenSale.addPaymentToken(address(token), 0, 18);
    }

    function test_AddPaymentTokenInvalidDecimals() public {
        MockERC20 token = new MockERC20("Test Token", "TEST");
        
        // Try to add payment token with decimals > 18 (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: invalid decimals");
        tokenSale.addPaymentToken(address(token), 100 * 10 ** 18, 19);
    }

    function test_ConfigureOraclePaymentTokenNotAllowed() public {
        MockERC20 token = new MockERC20("Test Token", "TEST");
        MockChainlinkOracle oracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "TEST/USD");
        
        // Try to configure oracle for token that's not added as payment token (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: payment token not allowed");
        tokenSale.configureOracle(address(token), address(oracle), 3600);
    }

    function test_ConfigureOracleInvalidOracleAddress() public {
        // Try to configure oracle with address(0) (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: invalid oracle address");
        tokenSale.configureOracle(address(usdc), address(0), 3600);
    }

    function test_UpdatePaymentTokenRateInvalidRate() public {
        // Try to update rate to zero (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: invalid rate");
        tokenSale.updatePaymentTokenRate(address(usdc), 0);
    }

    function test_UpdatePaymentTokenRatePaymentTokenNotAllowed() public {
        MockERC20 token = new MockERC20("Test Token", "TEST");
        
        // Try to update rate for token that's not added as payment token (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: token not allowed");
        tokenSale.updatePaymentTokenRate(address(token), 100 * 10 ** 18);
    }

    function test_RemoveOraclePaymentTokenNotAllowed() public {
        MockERC20 token = new MockERC20("Test Token", "TEST");
        
        // Try to remove oracle for token that's not added as payment token (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: payment token not allowed");
        tokenSale.removeOracle(address(token));
    }

    function test_SetOracleModePaymentTokenNotAllowed() public {
        MockERC20 token = new MockERC20("Test Token", "TEST");
        
        // Try to set oracle mode for token that's not added as payment token (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: payment token not allowed");
        tokenSale.setOracleMode(address(token), true);
    }

    function test_UpdateStalenessThresholdInvalidThreshold() public {
        MockChainlinkOracle oracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        
        // Configure oracle first
        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(oracle), 3600);
        
        // Try to update staleness threshold to zero (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: invalid threshold");
        tokenSale.updateStalenessThreshold(address(0), 0);
    }

    function test_UpdateStalenessThresholdPaymentTokenNotAllowed() public {
        MockERC20 token = new MockERC20("Test Token", "TEST");
        
        // Try to update staleness threshold for token that's not added as payment token (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: payment token not allowed");
        tokenSale.updateStalenessThreshold(address(token), 7200);
    }

    function test_UpdateDefaultStalenessThresholdInvalidThreshold() public {
        // Try to update default staleness threshold to zero (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: invalid threshold");
        tokenSale.updateDefaultStalenessThreshold(0);
    }

    function test_SetBaseRateInvalidBaseRate() public {
        // Try to set base rate to zero (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: invalid base rate");
        tokenSale.setBaseRate(address(usdc), 0);
    }

    function test_SetBaseRateBasePaymentTokenNotAllowed() public {
        MockERC20 token = new MockERC20("Test Token", "TEST");
        
        // Try to set base rate for token that's not added as payment token (should fail)
        vm.prank(admin);
        vm.expectRevert("TokenSale: base payment token not allowed");
        tokenSale.setBaseRate(address(token), 1 * 10 ** 18);
    }

    // ============ Zero Amount Edge Cases ============

    function test_PurchaseWithTokenZeroAmount() public {
        // Try to purchase with zero payment amount (should fail)
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), 0);
        vm.expectRevert("TokenSale: invalid payment amount");
        tokenSale.purchaseWithToken(address(usdc), 0, bytes32(0));
        vm.stopPrank();
    }

    function test_PurchaseWithETHZeroAmount() public {
        // Try to purchase with zero ETH (should fail)
        vm.startPrank(user1);
        vm.expectRevert("TokenSale: invalid payment amount");
        tokenSale.purchaseWithETH{value: 0}(bytes32(0));
        vm.stopPrank();
    }

    function test_CalculateTokensZeroAmount() public {
        // calculateTokens with zero amount should return 0
        uint256 calculated = tokenSale.calculateTokens(address(usdc), 0);
        assertEq(calculated, 0);
    }

    // ============ Edge Case Tests ============

    function test_EmergencyWithdrawSpecificAmount() public {
        // Send some ETH to contract
        vm.deal(address(tokenSale), 10 ether);
        
        address recipient = address(0x999);
        uint256 withdrawAmount = 3 ether;
        
        vm.prank(admin);
        tokenSale.emergencyWithdraw(address(0), recipient, withdrawAmount);

        assertEq(recipient.balance, withdrawAmount);
        assertEq(address(tokenSale).balance, 7 ether); // Remaining balance
    }

    function test_EmergencyWithdrawTokenSpecificAmount() public {
        uint256 totalAmount = 2000 * 10 ** usdc.decimals();
        usdc.mint(address(tokenSale), totalAmount);
        
        address recipient = address(0x999);
        uint256 withdrawAmount = 500 * 10 ** usdc.decimals();
        
        vm.prank(admin);
        tokenSale.emergencyWithdraw(address(usdc), recipient, withdrawAmount);

        assertEq(usdc.balanceOf(recipient), withdrawAmount);
        assertEq(usdc.balanceOf(address(tokenSale)), totalAmount - withdrawAmount);
    }

    function test_SaleTimeWindowInvalid() public {
        uint256 startTime = block.timestamp + 7 days;
        uint256 endTime = block.timestamp + 1 days; // End before start
        
        vm.prank(admin);
        vm.expectRevert("TokenSale: invalid time window");
        tokenSale.setSaleTimeWindow(startTime, endTime);
    }

    function test_HardCapExactAmount() public {
        // Account for initial supply from MockERC20 constructor
        uint256 initialSupply = baseToken.totalSupply();
        uint256 additionalTokens = 10000 * 10 ** 18; // 10,000 tokens
        uint256 cap = initialSupply + additionalTokens;
        vm.prank(admin);
        tokenSale.setHardCap(cap);

        // Purchase exactly at cap
        // Need to calculate payment amount that results in exactly additionalTokens tokens
        uint256 rate = tokenSale.paymentTokenRates(address(usdc));
        uint8 decimals = tokenSale.paymentTokenDecimals(address(usdc));
        uint256 paymentForCap = (additionalTokens * (10 ** decimals)) / rate;
        
        // Purchase slightly less first
        uint256 paymentAmount = paymentForCap - 1;
        vm.startPrank(user1);
        usdc.approve(address(tokenSale), paymentAmount * 2);
        tokenSale.purchaseWithToken(address(usdc), paymentAmount, bytes32(0));
        vm.stopPrank();

        // Now purchase the remaining amount (should succeed)
        uint256 currentSupply = baseToken.totalSupply();
        uint256 remaining = cap - currentSupply;
        uint256 remainingPayment = (remaining * (10 ** decimals)) / rate;
        
        vm.startPrank(user1);
        tokenSale.purchaseWithToken(address(usdc), remainingPayment, bytes32(0));
        vm.stopPrank();

        assertEq(baseToken.totalSupply(), cap);
    }

    function test_CalculateTokensWithOracle() public {
        MockERC20 eur = new MockERC20("Euro", "EUR");
        MockChainlinkOracle ethUsdOracle = new MockChainlinkOracle(8, 3000 * 10 ** 8, "ETH/USD");
        MockChainlinkOracle eurUsdOracle = new MockChainlinkOracle(8, 110000000, "EUR/USD");

        // Setup base rate and oracles
        uint256 baseRate = 1 * 10 ** 18;
        vm.prank(admin);
        tokenSale.addPaymentToken(address(eur), baseRate, 18);
        vm.prank(admin);
        tokenSale.setBaseRate(address(eur), baseRate);
        vm.prank(admin);
        tokenSale.configureOracle(address(eur), address(eurUsdOracle), 3600);
        vm.prank(admin);
        tokenSale.configureOracle(address(0), address(ethUsdOracle), 3600);

        // Calculate tokens for ETH purchase
        uint256 ethAmount = 1 ether;
        uint256 calculated = tokenSale.calculateTokens(address(0), ethAmount);
        
        assertGt(calculated, 0);
    }

    function test_CalculateTokensInvalidPaymentToken() public {
        address invalidToken = address(0x999);
        
        vm.expectRevert("TokenSale: payment token not allowed");
        tokenSale.calculateTokens(invalidToken, 1000 * 10 ** 18);
    }
}
