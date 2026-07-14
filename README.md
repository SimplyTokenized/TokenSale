# Token Sale Contract

An upgradeable token sale contract where users can purchase newly minted base tokens by paying with specified tokens (or ETH). Features optional whitelisting, configurable payment tokens, and flexible rate management.

## ✨ Features

- ✅ **Proxy Contract Support** - Fully upgradeable using OpenZeppelin's transparent proxy pattern
- 💰 **Multiple Payment Tokens** - Support for any ERC20 token or ETH as payment
- 📋 **Optional Whitelisting** - Enable/disable whitelist requirement for purchases
- 🪙 **Configurable Rates** - Define exchange rates for each payment token
- 📊 **Purchase Statistics** - Track purchases per user and per payment token
- ⏸️ **Pausable** - Admin can pause/unpause sales
- 🔒 **Access Control** - Role-based access control for admin functions
- 🛡️ **Reentrancy Protection** - Protected against reentrancy attacks
- 💸 **Payment Forwarding** - Payments are automatically forwarded to a designated recipient

## 🚀 Quick Start

### Prerequisites

1. Install dependencies:
```bash
npm run install:deps
# Or manually:
forge install OpenZeppelin/openzeppelin-contracts-upgradeable OpenZeppelin/openzeppelin-foundry-upgrades OpenZeppelin/openzeppelin-contracts
```

2. Set up environment variables in `.env`:
```bash
BASE_TOKEN=<address_of_base_token>  # The ERC20 token being sold (must have MINTER_ROLE)
PAYMENT_RECIPIENT=<address_to_receive_payments>
ADMIN=<admin_address>
```

### Build

```bash
npm run build
```

### Test

```bash
# Run all tests
npm run test

# Run with gas report
npm run test:gas

# Run with verbose output
npm run test:verbose
```

### Deploy

```bash
# Local deployment
npm run deploy:local

# Testnet deployment
npm run deploy:testnet
```

## 📖 Contract Functions

### Admin Functions

#### Payment Token Management
- `addPaymentToken(address paymentToken, uint256 tokensPerPayment, uint8 paymentTokenDecimals)` - Add a payment token with its rate
- `removePaymentToken(address paymentToken)` - Remove a payment token
- `updatePaymentTokenRate(address paymentToken, uint256 newRate)` - Update the rate for a payment token

#### Whitelist Management
- `addToWhitelist(address account)` - Add address to whitelist
- `removeFromWhitelist(address account)` - Remove address from whitelist
- `updateWhitelistRequirement(bool requireWhitelist)` - Enable/disable whitelist requirement

#### Configuration
- `updatePaymentRecipient(address paymentRecipient)` - Update payment recipient address
- `pause()` - Pause token sales
- `unpause()` - Unpause token sales

### Purchase Functions

- `purchaseWithToken(address paymentToken, uint256 paymentAmount, uint256 minTokensOut, bytes32 orderId)` - Purchase tokens with ERC20 payment token
- `purchaseWithETH(uint256 minTokensOut, bytes32 orderId)` - Purchase tokens with ETH (payable function)

`minTokensOut` is slippage protection: the transaction reverts if the rate changed and the buyer would receive fewer tokens than specified (use the value from `calculateTokens`, or 0 to accept any rate). `orderId` is an optional identifier, unique per buyer (`bytes32(0)` = none).

### View Functions

- `calculateTokens(address paymentToken, uint256 paymentAmount)` - Calculate tokens for a payment amount
- `getUserPurchases(address user)` - Get total tokens purchased by a user
- `getUserPurchasesByToken(address user, address paymentToken)` - Get tokens purchased using a specific payment token
- `paymentTokenRates(address)` - Get rate for a payment token
- `paymentTokenDecimals(address)` - Get decimals for a payment token
- `allowedPaymentTokens(address)` - Check if payment token is allowed

## 🔐 Roles

| Role | Description |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Full admin access, can upgrade contract |
| `ADMIN_ROLE` | Can manage payment tokens, whitelist, and configuration |

## 📝 Setup Process

### 1. Deploy Contract

Deploy the TokenSale contract using the deployment script.

### 2. Grant MINTER_ROLE

The TokenSale contract must have `MINTER_ROLE` on the base token (ERC20 contract) to mint tokens directly:

```solidity
// On the base token contract (from ERC20 folder)
bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
baseToken.grantRole(MINTER_ROLE, tokenSaleAddress);
```

Once granted, the TokenSale contract can directly call `mint(address, uint256)` on the base token contract, which will automatically check for MINTER_ROLE.

### 3. Add Payment Tokens

Configure payment tokens with their rates:

```solidity
// Example: 1 USDC (6 decimals) = 100 BASE tokens (18 decimals)
// Rate = 100 * 10^18
tokenSale.addPaymentToken(usdcAddress, 100 * 10**18, 6);

// Example: 1 ETH = 1000 BASE tokens
// Rate = 1000 * 10^18
tokenSale.addPaymentToken(address(0), 1000 * 10**18, 18);
```

### 4. (Optional) Enable Whitelist

```solidity
tokenSale.updateWhitelistRequirement(true);
tokenSale.addToWhitelist(userAddress);
```

## 💡 Example Usage

### Purchase with ERC20 Token

```solidity
// User approves payment token
usdc.approve(tokenSaleAddress, 1000 * 10**6);

// Purchase tokens (minTokensOut from calculateTokens, orderId optional)
uint256 minOut = tokenSale.calculateTokens(usdcAddress, 1000 * 10**6);
uint256 tokens = tokenSale.purchaseWithToken(usdcAddress, 1000 * 10**6, minOut, bytes32(0));
```

### Purchase with ETH

```solidity
// Purchase tokens with ETH
uint256 minOut = tokenSale.calculateTokens(address(0), 1 ether);
uint256 tokens = tokenSale.purchaseWithETH{value: 1 ether}(minOut, bytes32(0));
```

### Calculate Tokens Before Purchase

```solidity
uint256 paymentAmount = 1000 * 10**6; // 1000 USDC
uint256 expectedTokens = tokenSale.calculateTokens(usdcAddress, paymentAmount);
```

## 📊 Rate Calculation

The rate is stored as: **base tokens (18 decimals) per 1 unit of payment token**

### Formula
```
baseTokens = (paymentAmount * rate) / (10^paymentTokenDecimals)
```

### Examples

**USDC (6 decimals):**
- Rate: 100 * 10^18 (100 base tokens per 1 USDC)
- Payment: 1000 USDC = 1000 * 10^6
- Calculation: (1000 * 10^6 * 100 * 10^18) / 10^6 = 100,000 * 10^18 base tokens

**ETH (18 decimals):**
- Rate: 1000 * 10^18 (1000 base tokens per 1 ETH)
- Payment: 1 ETH = 1 * 10^18
- Calculation: (1 * 10^18 * 1000 * 10^18) / 10^18 = 1000 * 10^18 base tokens

## ⚠️ Important Notes

1. **MINTER_ROLE Required**: The TokenSale contract must have `MINTER_ROLE` on the base token contract
2. **Payment Forwarding**: All payments are immediately forwarded to the `paymentRecipient` address
3. **Token Minting**: Base tokens are minted directly to the buyer's address
4. **Rate Precision**: Rates should be calculated carefully to account for token decimals
5. **Whitelist**: Whitelist is optional and disabled by default

## 🔄 Upgradeability

The contract uses OpenZeppelin's transparent proxy pattern:
- **Proxy Address**: Remains constant (this is the address users interact with)
- **Implementation**: Can be upgraded by `DEFAULT_ADMIN_ROLE`
- **State**: Stored in proxy, persists across upgrades

## ⚠️ Security Considerations

- ✅ **Reentrancy Protection**: All purchase functions use `nonReentrant` (OpenZeppelin `ReentrancyGuardTransient`, requires a Cancun/EIP-1153 chain)
- ✅ **Access Control**: Admin functions protected with role checks
- ✅ **Pausable**: Can pause sales in emergencies
- ✅ **Whitelist**: Optional additional security layer
- ✅ **SafeERC20**: Uses SafeERC20 for token transfers
- ✅ **Input Validation**: All inputs are validated; payment token decimals are verified against the token contract
- ✅ **Slippage Protection**: Buyers pass `minTokensOut`; purchases revert if the rate moved against them
- ✅ **Fail-Closed Oracles**: If oracle mode is on and the price is stale, invalid, or out of the configured bounds, purchases revert (no silent fallback to a manual rate). To sell at the manual rate, the admin must explicitly call `setOracleMode(token, false)`
- ✅ **Oracle Hardening**: Per-feed staleness thresholds, optional min/max price bounds (`setOraclePriceBounds`) against pinned Chainlink circuit breakers, and an optional L2 sequencer uptime check (`setSequencerUptimeFeed` — required on Arbitrum/Optimism/Base)
- ✅ **Per-User Limits**: Enforced against tokens purchased through the sale (`totalPurchased`), so they cannot be bypassed by moving tokens to another wallet or griefed by unsolicited transfers
- ✅ **Order IDs**: Scoped per buyer, so a third party cannot front-run and burn someone else's orderId

### Operational requirements

- **Use a multisig (ideally with a timelock) for the admin and proxy admin.** The admin can change rates, redirect payments, withdraw funds, and upgrade the implementation — a single compromised EOA compromises the entire sale.
- **Off-chain order reconciliation** must verify the buyer address and amounts from the `TokensPurchased` event, never the orderId alone.
- **Do not allow fee-on-transfer or rebasing tokens as payment tokens** — buyers would be credited for the nominal amount while the recipient receives less.
- **Hard cap** is measured against the base token's `totalSupply()`: tokens minted elsewhere consume the cap and burns free it up.

## 📚 Documentation

Auto-generated API documentation from NatSpec comments is available in the `docs/` directory. Generate it with:

```bash
npm run docgen
```

Or generate and serve it locally (opens in browser automatically):

```bash
npm run docgen:serve
```

## 📄 License

MIT
