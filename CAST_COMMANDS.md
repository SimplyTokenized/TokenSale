# Cast Commands for Token Sale Testing

This document contains all the `cast` commands to interact with and test the TokenSale contract.

## Prerequisites

- Start a local Anvil node: `anvil` (runs on `http://localhost:8545`)
- Deploy a base token contract first (ERC20 with MINTER_ROLE)
- Deploy the TokenSale contract (see deployment section)
- Set environment variables:
  ```bash
  export TOKEN_SALE_ADDRESS=<your_token_sale_address>
  export BASE_TOKEN_ADDRESS=<your_base_token_address>
  export RPC_URL=http://localhost:8545  # or your testnet RPC
  export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80  # Anvil default
  export ADMIN=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266  # Anvil default account
  export PAYMENT_RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8  # Account 1
  ```

## Default Anvil Accounts (Local Testing)

- **Account 0 (Deployer/Admin)**: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- **Account 1**: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8`
- **Account 2**: `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`
- **Private Key (Account 0)**: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

---

## 1. Contract Information (Read Operations)

### Get Base Token Address
```bash
cast call $TOKEN_SALE_ADDRESS "baseToken()(address)" --rpc-url $RPC_URL
```

### Get Payment Recipient
```bash
cast call $TOKEN_SALE_ADDRESS "paymentRecipient()(address)" --rpc-url $RPC_URL
```

### Check if Whitelist is Required
```bash
cast call $TOKEN_SALE_ADDRESS "requireWhitelist()(bool)" --rpc-url $RPC_URL
```

### Check if Address is Whitelisted
```bash
cast call $TOKEN_SALE_ADDRESS "whitelist(address)(bool)" <ADDRESS> --rpc-url $RPC_URL
```

**Example:**
```bash
cast call $TOKEN_SALE_ADDRESS "whitelist(address)(bool)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url $RPC_URL
```

### Check if Payment Token is Allowed
```bash
cast call $TOKEN_SALE_ADDRESS "allowedPaymentTokens(address)(bool)" <TOKEN_ADDRESS> --rpc-url $RPC_URL
```

**Example (for ETH):**
```bash
cast call $TOKEN_SALE_ADDRESS "allowedPaymentTokens(address)(bool)" 0x0000000000000000000000000000000000000000 --rpc-url $RPC_URL
```

### Get Payment Token Rate
```bash
cast call $TOKEN_SALE_ADDRESS "paymentTokenRates(address)(uint256)" <TOKEN_ADDRESS> --rpc-url $RPC_URL
```

### Get Payment Token Decimals
```bash
cast call $TOKEN_SALE_ADDRESS "paymentTokenDecimals(address)(uint8)" <TOKEN_ADDRESS> --rpc-url $RPC_URL
```

### Check if Paused
```bash
cast call $TOKEN_SALE_ADDRESS "paused()(bool)" --rpc-url $RPC_URL
```

### Get Sale Configuration
```bash
# Hard cap
cast call $TOKEN_SALE_ADDRESS "hardCap()(uint256)" --rpc-url $RPC_URL

# Min purchase amount
cast call $TOKEN_SALE_ADDRESS "minPurchaseAmount()(uint256)" --rpc-url $RPC_URL

# Max purchase per user
cast call $TOKEN_SALE_ADDRESS "maxPurchasePerUser()(uint256)" --rpc-url $RPC_URL

# Sale start time
cast call $TOKEN_SALE_ADDRESS "saleStartTime()(uint256)" --rpc-url $RPC_URL

# Sale end time
cast call $TOKEN_SALE_ADDRESS "saleEndTime()(uint256)" --rpc-url $RPC_URL
```

### Get User Purchase Statistics
```bash
# Total purchased by user
cast call $TOKEN_SALE_ADDRESS "getUserPurchases(address)(uint256)" <USER_ADDRESS> --rpc-url $RPC_URL

# Purchased by user with specific payment token
cast call $TOKEN_SALE_ADDRESS "getUserPurchasesByToken(address,address)(uint256)" <USER_ADDRESS> <TOKEN_ADDRESS> --rpc-url $RPC_URL
```

### Get Total Sales Statistics
```bash
# Total tokens sold
cast call $TOKEN_SALE_ADDRESS "totalSales()(uint256)" --rpc-url $RPC_URL

# Total revenue (in base token units)
cast call $TOKEN_SALE_ADDRESS "totalRevenue()(uint256)" --rpc-url $RPC_URL

# Revenue by payment token
cast call $TOKEN_SALE_ADDRESS "revenueByToken(address)(uint256)" <TOKEN_ADDRESS> --rpc-url $RPC_URL
```

### Calculate Tokens for Payment Amount
```bash
cast call $TOKEN_SALE_ADDRESS "calculateTokens(address,uint256)(uint256)" <TOKEN_ADDRESS> <AMOUNT> --rpc-url $RPC_URL
```

**Example:**
```bash
# Calculate tokens for 1 ETH (1000000000000000000 wei)
cast call $TOKEN_SALE_ADDRESS "calculateTokens(address,uint256)(uint256)" 0x0000000000000000000000000000000000000000 1000000000000000000 --rpc-url $RPC_URL
```

---

## 2. Role Management

### Check if Address has ADMIN_ROLE
```bash
ADMIN_ROLE=$(cast keccak "ADMIN_ROLE")
cast call $TOKEN_SALE_ADDRESS "hasRole(bytes32,address)(bool)" $ADMIN_ROLE <ADDRESS> --rpc-url $RPC_URL
```

**Example:**
```bash
ADMIN_ROLE=$(cast keccak "ADMIN_ROLE")
cast call $TOKEN_SALE_ADDRESS "hasRole(bytes32,address)(bool)" $ADMIN_ROLE 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url $RPC_URL
```

### Check if Address has WHITELIST_ROLE
```bash
WHITELIST_ROLE=$(cast keccak "WHITELIST_ROLE")
cast call $TOKEN_SALE_ADDRESS "hasRole(bytes32,address)(bool)" $WHITELIST_ROLE <ADDRESS> --rpc-url $RPC_URL
```

### Check if Address has DEFAULT_ADMIN_ROLE
```bash
# DEFAULT_ADMIN_ROLE is 0x0000000000000000000000000000000000000000000000000000000000000000
cast call $TOKEN_SALE_ADDRESS "hasRole(bytes32,address)(bool)" 0x0000000000000000000000000000000000000000000000000000000000000000 <ADDRESS> --rpc-url $RPC_URL
```

### Grant ADMIN_ROLE (requires DEFAULT_ADMIN_ROLE)
```bash
ADMIN_ROLE=$(cast keccak "ADMIN_ROLE")
cast send $TOKEN_SALE_ADDRESS "grantRole(bytes32,address)" $ADMIN_ROLE <ADDRESS> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Grant WHITELIST_ROLE (requires DEFAULT_ADMIN_ROLE or ADMIN_ROLE)
```bash
WHITELIST_ROLE=$(cast keccak "WHITELIST_ROLE")
cast send $TOKEN_SALE_ADDRESS "grantRole(bytes32,address)" $WHITELIST_ROLE <ADDRESS> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Revoke Role
```bash
ROLE=$(cast keccak "<ROLE_NAME>")
cast send $TOKEN_SALE_ADDRESS "revokeRole(bytes32,address)" $ROLE <ADDRESS> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

---

## 3. Payment Token Management (requires ADMIN_ROLE)

### Add Payment Token
```bash
cast send $TOKEN_SALE_ADDRESS "addPaymentToken(address,uint256,uint8)" <TOKEN_ADDRESS> <RATE> <DECIMALS> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

**Example (add ETH with rate 1 ETH = 1000 tokens, 18 decimals):**
```bash
# Rate: 1000 * 10^18 (1000 tokens per 1 ETH)
cast send $TOKEN_SALE_ADDRESS "addPaymentToken(address,uint256,uint8)" 0x0000000000000000000000000000000000000000 1000000000000000000000 18 --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

**Example (add USDC with rate 1 USDC = 100 tokens, 6 decimals):**
```bash
# Rate: 100 * 10^18 (100 tokens per 1 USDC)
# USDC has 6 decimals
cast send $TOKEN_SALE_ADDRESS "addPaymentToken(address,uint256,uint8)" <USDC_ADDRESS> 100000000000000000000 6 --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Remove Payment Token
```bash
cast send $TOKEN_SALE_ADDRESS "removePaymentToken(address)" <TOKEN_ADDRESS> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Update Payment Token Rate
```bash
cast send $TOKEN_SALE_ADDRESS "updatePaymentTokenRate(address,uint256)" <TOKEN_ADDRESS> <NEW_RATE> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

---

## 4. Whitelist Management (requires ADMIN_ROLE or WHITELIST_ROLE)

### Add Address to Whitelist
```bash
cast send $TOKEN_SALE_ADDRESS "addToWhitelist(address)" <ADDRESS> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

**Example:**
```bash
cast send $TOKEN_SALE_ADDRESS "addToWhitelist(address)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Remove Address from Whitelist
```bash
cast send $TOKEN_SALE_ADDRESS "removeFromWhitelist(address)" <ADDRESS> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Update Whitelist Requirement (requires ADMIN_ROLE)
```bash
# Enable whitelist requirement
cast send $TOKEN_SALE_ADDRESS "updateWhitelistRequirement(bool)" true --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# Disable whitelist requirement
cast send $TOKEN_SALE_ADDRESS "updateWhitelistRequirement(bool)" false --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

---

## 5. Pause/Unpause Operations (requires ADMIN_ROLE)

### Pause Sales
```bash
cast send $TOKEN_SALE_ADDRESS "pause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Unpause Sales
```bash
cast send $TOKEN_SALE_ADDRESS "unpause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

---

## 6. Sale Configuration (requires ADMIN_ROLE)

### Configure Sale (all parameters at once)
```bash
cast send $TOKEN_SALE_ADDRESS "configureSale(uint256,uint256,uint256,uint256,uint256)" \
  <HARD_CAP> <MIN_PURCHASE> <MAX_PURCHASE_PER_USER> <START_TIME> <END_TIME> \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

**Example:**
```bash
# Hard cap: 1000000 tokens, Min: 100 tokens, Max per user: 10000 tokens
# Start time: now + 1 hour, End time: now + 1 day (using current timestamp)
cast send $TOKEN_SALE_ADDRESS "configureSale(uint256,uint256,uint256,uint256,uint256)" \
  1000000000000000000000000 100000000000000000000 10000000000000000000000 0 0 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Set Hard Cap
```bash
# 0 = unlimited
cast send $TOKEN_SALE_ADDRESS "setHardCap(uint256)" <HARD_CAP> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Set Minimum Purchase Amount
```bash
# 0 = no minimum
cast send $TOKEN_SALE_ADDRESS "setMinPurchaseAmount(uint256)" <MIN_AMOUNT> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Set Maximum Purchase Per User
```bash
# 0 = unlimited
cast send $TOKEN_SALE_ADDRESS "setMaxPurchasePerUser(uint256)" <MAX_AMOUNT> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Set Maximum Purchase for Specific User
```bash
# 0 = use global limit
cast send $TOKEN_SALE_ADDRESS "setMaxPurchaseForUser(address,uint256)" <USER_ADDRESS> <MAX_AMOUNT> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Set Sale Time Window
```bash
# 0 = no restriction
cast send $TOKEN_SALE_ADDRESS "setSaleTimeWindow(uint256,uint256)" <START_TIME> <END_TIME> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

---

## 7. Oracle Configuration (requires ADMIN_ROLE)

### Configure Oracle for Payment Token
```bash
cast send $TOKEN_SALE_ADDRESS "configureOracle(address,address,uint256)" \
  <TOKEN_ADDRESS> <ORACLE_ADDRESS> <STALENESS_THRESHOLD> \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

**Example:**
```bash
# Configure ETH/USD oracle with 24 hour staleness threshold (86400 seconds)
cast send $TOKEN_SALE_ADDRESS "configureOracle(address,address,uint256)" \
  0x0000000000000000000000000000000000000000 <ORACLE_ADDRESS> 86400 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Remove Oracle
```bash
cast send $TOKEN_SALE_ADDRESS "removeOracle(address)" <TOKEN_ADDRESS> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Set Oracle Mode (enable/disable)
```bash
# Enable oracle
cast send $TOKEN_SALE_ADDRESS "setOracleMode(address,bool)" <TOKEN_ADDRESS> true --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# Disable oracle (use manual rate)
cast send $TOKEN_SALE_ADDRESS "setOracleMode(address,bool)" <TOKEN_ADDRESS> false --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Update Staleness Threshold
```bash
cast send $TOKEN_SALE_ADDRESS "updateStalenessThreshold(address,uint256)" <TOKEN_ADDRESS> <THRESHOLD_SECONDS> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Update Default Staleness Threshold
```bash
cast send $TOKEN_SALE_ADDRESS "updateDefaultStalenessThreshold(uint256)" <THRESHOLD_SECONDS> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

---

## 8. Base Rate Configuration (requires ADMIN_ROLE)

### Set Base Rate
```bash
cast send $TOKEN_SALE_ADDRESS "setBaseRate(address,uint256)" <BASE_PAYMENT_TOKEN> <BASE_RATE> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

**Example:**
```bash
# Set base payment token to EUR token with rate 1 token = 1 EUR
cast send $TOKEN_SALE_ADDRESS "setBaseRate(address,uint256)" <EUR_TOKEN_ADDRESS> 1000000000000000000 --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Update Base Rate
```bash
cast send $TOKEN_SALE_ADDRESS "updateBaseRate(uint256)" <NEW_BASE_RATE> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Update Base Payment Token
```bash
cast send $TOKEN_SALE_ADDRESS "updateBasePaymentToken(address)" <NEW_BASE_PAYMENT_TOKEN> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

---

## 9. Purchase Functions

### Purchase Tokens with ERC20 Token
```bash
cast send $TOKEN_SALE_ADDRESS "purchaseWithToken(address,uint256,bytes32)" \
  <TOKEN_ADDRESS> <AMOUNT> <ORDER_ID> \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

**Example (with order ID):**
```bash
# Purchase with 100 USDC (6 decimals = 100000000)
ORDER_ID=$(cast keccak "order-123")
cast send $TOKEN_SALE_ADDRESS "purchaseWithToken(address,uint256,bytes32)" \
  <USDC_ADDRESS> 100000000 $ORDER_ID \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

**Example (without order ID):**
```bash
# Use zero bytes32 for no order ID
cast send $TOKEN_SALE_ADDRESS "purchaseWithToken(address,uint256,bytes32)" \
  <USDC_ADDRESS> 100000000 0x0000000000000000000000000000000000000000000000000000000000000000 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

**Note:** Before purchasing with an ERC20 token, you need to approve the TokenSale contract to spend tokens:
```bash
cast send <TOKEN_ADDRESS> "approve(address,uint256)" $TOKEN_SALE_ADDRESS <AMOUNT> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Purchase Tokens with ETH
```bash
cast send $TOKEN_SALE_ADDRESS "purchaseWithETH(bytes32)" <ORDER_ID> --value <AMOUNT_IN_WEI> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

**Example:**
```bash
# Purchase with 0.1 ETH (100000000000000000 wei) without order ID
cast send $TOKEN_SALE_ADDRESS "purchaseWithETH(bytes32)" 0x0000000000000000000000000000000000000000000000000000000000000000 --value 100000000000000000 --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# Purchase with 0.1 ETH with order ID
ORDER_ID=$(cast keccak "eth-order-456")
cast send $TOKEN_SALE_ADDRESS "purchaseWithETH(bytes32)" $ORDER_ID --value 100000000000000000 --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

---

## 10. Admin Utility Functions

### Update Payment Recipient (requires ADMIN_ROLE)
```bash
cast send $TOKEN_SALE_ADDRESS "updatePaymentRecipient(address)" <NEW_RECIPIENT> --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

### Emergency Withdrawal (requires ADMIN_ROLE)
```bash
# Withdraw ETH (0 = withdraw all)
cast send $TOKEN_SALE_ADDRESS "emergencyWithdraw(address,address,uint256)" \
  0x0000000000000000000000000000000000000000 <RECIPIENT> <AMOUNT> \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# Withdraw ERC20 token (0 = withdraw all)
cast send $TOKEN_SALE_ADDRESS "emergencyWithdraw(address,address,uint256)" \
  <TOKEN_ADDRESS> <RECIPIENT> <AMOUNT> \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

---

## 11. Complete Testing Workflow

Here's a complete workflow to test TokenSale functionality:

```bash
# 1. Set variables
export TOKEN_SALE_ADDRESS=<your_deployed_token_sale_address>
export BASE_TOKEN_ADDRESS=<your_base_token_address>
export RPC_URL=http://localhost:8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export ADMIN=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export PAYMENT_RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
export BUYER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

# 2. Check contract info
cast call $TOKEN_SALE_ADDRESS "baseToken()(address)" --rpc-url $RPC_URL
cast call $TOKEN_SALE_ADDRESS "paymentRecipient()(address)" --rpc-url $RPC_URL
cast call $TOKEN_SALE_ADDRESS "requireWhitelist()(bool)" --rpc-url $RPC_URL

# 3. Grant MINTER_ROLE to TokenSale contract on base token
MINTER_ROLE=$(cast keccak "MINTER_ROLE")
cast send $BASE_TOKEN_ADDRESS "grantRole(bytes32,address)" $MINTER_ROLE $TOKEN_SALE_ADDRESS --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# 4. Add ETH as payment token (rate: 1 ETH = 1000 tokens)
cast send $TOKEN_SALE_ADDRESS "addPaymentToken(address,uint256,uint8)" \
  0x0000000000000000000000000000000000000000 1000000000000000000000 18 \
  --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# 5. Check if ETH is allowed
cast call $TOKEN_SALE_ADDRESS "allowedPaymentTokens(address)(bool)" \
  0x0000000000000000000000000000000000000000 --rpc-url $RPC_URL

# 6. Calculate tokens for 0.1 ETH
cast call $TOKEN_SALE_ADDRESS "calculateTokens(address,uint256)(uint256)" \
  0x0000000000000000000000000000000000000000 100000000000000000 --rpc-url $RPC_URL

# 7. Enable whitelist and add buyer to whitelist
cast send $TOKEN_SALE_ADDRESS "updateWhitelistRequirement(bool)" true --private-key $PRIVATE_KEY --rpc-url $RPC_URL
cast send $TOKEN_SALE_ADDRESS "addToWhitelist(address)" $BUYER --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# 8. Check if buyer is whitelisted
cast call $TOKEN_SALE_ADDRESS "whitelist(address)(bool)" $BUYER --rpc-url $RPC_URL

# 9. Purchase tokens with ETH (as buyer, requires buyer's private key)
BUYER_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389ac9e75b579d0e2e7e5b1e7b2e2b2e2b2
cast send $TOKEN_SALE_ADDRESS "purchaseWithETH(bytes32)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  --value 100000000000000000 --private-key $BUYER_PRIVATE_KEY --rpc-url $RPC_URL

# 10. Check buyer's purchases
cast call $TOKEN_SALE_ADDRESS "getUserPurchases(address)(uint256)" $BUYER --rpc-url $RPC_URL
cast call $TOKEN_SALE_ADDRESS "getUserPurchasesByToken(address,address)(uint256)" \
  $BUYER 0x0000000000000000000000000000000000000000 --rpc-url $RPC_URL

# 11. Check total sales
cast call $TOKEN_SALE_ADDRESS "totalSales()(uint256)" --rpc-url $RPC_URL
cast call $TOKEN_SALE_ADDRESS "totalRevenue()(uint256)" --rpc-url $RPC_URL

# 12. Check buyer's token balance
cast call $BASE_TOKEN_ADDRESS "balanceOf(address)(uint256)" $BUYER --rpc-url $RPC_URL

# 13. Pause sales
cast send $TOKEN_SALE_ADDRESS "pause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# 14. Check if paused
cast call $TOKEN_SALE_ADDRESS "paused()(bool)" --rpc-url $RPC_URL

# 15. Unpause sales
cast send $TOKEN_SALE_ADDRESS "unpause()" --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# 16. Disable whitelist requirement
cast send $TOKEN_SALE_ADDRESS "updateWhitelistRequirement(bool)" false --private-key $PRIVATE_KEY --rpc-url $RPC_URL

# 17. Remove buyer from whitelist
cast send $TOKEN_SALE_ADDRESS "removeFromWhitelist(address)" $BUYER --private-key $PRIVATE_KEY --rpc-url $RPC_URL
```

---

## 12. Helper Scripts

### Get all role hashes
```bash
echo "DEFAULT_ADMIN_ROLE: 0x0000000000000000000000000000000000000000000000000000000000000000"
echo "ADMIN_ROLE: $(cast keccak "ADMIN_ROLE")"
echo "WHITELIST_ROLE: $(cast keccak "WHITELIST_ROLE")"
echo "MINTER_ROLE: $(cast keccak "MINTER_ROLE")"
```

### Convert wei to token units
```bash
# Convert 1 ETH to wei
cast --to-wei 1 ether

# Convert wei to ETH
cast --from-wei <amount_in_wei> ether

# Convert 1 token (assuming 18 decimals) to wei
cast --to-wei 1 ether
```

### Get current block number and timestamp
```bash
# Block number
cast block-number --rpc-url $RPC_URL

# Block timestamp (requires jq)
cast block --rpc-url $RPC_URL | jq -r '.timestamp'

# Current timestamp in seconds (for sale time configuration)
date +%s
```

### Get account balance (ETH)
```bash
cast balance <ADDRESS> --rpc-url $RPC_URL
```

### Generate order ID
```bash
# Generate order ID from string
ORDER_ID=$(cast keccak "order-123")
echo $ORDER_ID

# Or use zero bytes32 for no order ID
ORDER_ID=0x0000000000000000000000000000000000000000000000000000000000000000
```

---

## Notes

- All amounts are in the token's smallest unit (wei equivalent). For tokens with 18 decimals, 1 token = 1000000000000000000 wei.
- The admin address automatically gets `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`, and `WHITELIST_ROLE` upon initialization.
- `DEFAULT_ADMIN_ROLE` can grant/revoke all other roles.
- Before purchasing with an ERC20 token, approve the TokenSale contract to spend tokens.
- ETH is represented as `address(0)` (0x0000000000000000000000000000000000000000).
- Order IDs must be unique if provided (non-zero bytes32). Use zero bytes32 to skip order ID tracking.
- When using testnet, replace `$RPC_URL` with your testnet RPC URL and use appropriate private keys.
- Always verify you have the required role before attempting operations that require specific roles.
- The TokenSale contract must have `MINTER_ROLE` on the base token contract to mint tokens to buyers.
- Payment tokens are automatically forwarded to the payment recipient address.
- Sale limits (hard cap, min/max purchase, time window) are optional. Use 0 to disable restrictions.
