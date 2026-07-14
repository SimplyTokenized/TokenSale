# Token Sale Contract

An upgradeable token sale contract where users purchase newly minted base tokens by paying with approved ERC20 tokens or ETH. Supports fixed rates, Chainlink-oracle-derived rates, optional whitelisting, per-user and global sale limits, and time-boxed sale windows.

## ✨ Features

- **Upgradeable** — OpenZeppelin transparent proxy pattern
- **Multiple Payment Tokens** — any approved ERC20 token or native ETH
- **Fixed or Oracle Pricing** — manual rates per token, or rates derived from Chainlink price feeds relative to a configurable base payment token
- **Oracle Hardening** — per-feed staleness thresholds, optional price bounds, optional L2 sequencer uptime check; fail-closed on any oracle error
- **Slippage Protection** — buyers specify the minimum tokens they accept
- **Sale Limits** — hard cap, minimum purchase, per-user limits (global and per-address overrides), start/end time window
- **Optional Whitelisting** — restrict purchases to approved addresses
- **Order IDs** — optional per-buyer order identifiers for off-chain reconciliation
- **Purchase Statistics** — totals per user, per payment token, and per sale
- **Pausable** — admin can halt sales in an emergency
- **Role-Based Access Control** — separate admin and whitelist-manager roles
- **Payment Forwarding** — payments go directly to a designated recipient; the contract holds no funds

## 📋 Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js ≥ 18 (for the optional Node.js deployment path and the upgrade-safety validator)
- A deployment target that supports the **Cancun** hardfork (EIP-1153 transient storage) — Ethereum mainnet, Sepolia, and current Arbitrum/Optimism/Base releases all qualify

## 🚀 Quick Start

### Install

```bash
npm install          # Node.js tooling (ethers, solc, dotenv)
npm run install:deps # Foundry libraries (OpenZeppelin, Chainlink)
```

### Configure

```bash
cp .env.example .env
# then fill in BASE_TOKEN, PAYMENT_RECIPIENT, ADMIN, and network settings
```

### Build & Test

```bash
npm run build

npm run test          # full unit suite (deterministic, no network access)
npm run test:all      # includes the Sepolia live-oracle fork tests
npm run test:gas      # with gas report
```

### Deploy

```bash
npm run deploy:local    # local Anvil node
npm run deploy:sepolia  # Ethereum Sepolia (verifies on Etherscan)
npm run deploy:nodejs   # Node.js/ethers deployment path (see DEPLOY_NODEJS.md)
```

## 📖 Contract Functions

### Purchase Functions

- `purchaseWithToken(address paymentToken, uint256 paymentAmount, uint256 minTokensOut, bytes32 orderId)` — purchase with an approved ERC20 token
- `purchaseWithETH(uint256 minTokensOut, bytes32 orderId)` — purchase with ETH (payable)

`minTokensOut` is slippage protection: the transaction reverts if the rate changed and the buyer would receive fewer tokens than specified. Use the value from `calculateTokens`, or `0` to accept any rate. `orderId` is an optional identifier, unique per buyer (`bytes32(0)` = none).

### View Functions

- `calculateTokens(address paymentToken, uint256 paymentAmount)` — quote the base tokens for a payment amount (reverts if oracle data is unavailable — fail-closed)
- `getUserPurchases(address user)` / `totalPurchased(address)` — total base tokens a user purchased through the sale
- `getUserPurchasesByToken(address user, address paymentToken)` — purchases per payment token
- `totalSales()`, `revenueByToken(address)` — sale-wide statistics
- `paymentTokenRates(address)`, `paymentTokenDecimals(address)`, `allowedPaymentTokens(address)` — payment token configuration
- `usedOrderIds(address buyer, bytes32 orderId)` — whether a buyer has used an order ID

### Admin Functions

#### Payment Token Management
- `addPaymentToken(address paymentToken, uint256 tokensPerPayment, uint8 paymentTokenDecimals)` — add a payment token (decimals are verified against the token contract when available; ETH must be added with 18 decimals)
- `removePaymentToken(address paymentToken)` — remove a payment token and **all** of its configuration (rate, decimals, oracle settings, price bounds); the active base payment token cannot be removed
- `updatePaymentTokenRate(address paymentToken, uint256 newRate)` — update a manual rate

#### Base Rate & Oracle Pricing
- `setBaseRate(address basePaymentToken, uint256 baseRate)` — set the anchor: how many base tokens one unit of the base payment token buys
- `updateBaseRate(uint256 newBaseRate)` / `updateBasePaymentToken(address newBasePaymentToken)`
- `configureOracle(address paymentToken, address oracle, uint256 stalenessThreshold)` — attach a Chainlink feed to a payment token and enable oracle mode; set the threshold to the feed's heartbeat
- `setOracleMode(address paymentToken, bool useOracle)` — switch between oracle and manual pricing
- `removeOracle(address paymentToken)` — remove the oracle configuration (clears threshold and bounds)
- `updateStalenessThreshold(address paymentToken, uint256 newThreshold)` / `updateDefaultStalenessThreshold(uint256 newThreshold)`
- `setOraclePriceBounds(address paymentToken, uint256 minPrice, uint256 maxPrice)` — optional sanity bounds (in feed decimals) against a pinned Chainlink circuit breaker
- `setSequencerUptimeFeed(address feed, uint256 gracePeriod)` — L2 sequencer uptime check; **required on L2 deployments**, `address(0)` disables it for L1

#### Sale Limits
- `configureSale(uint256 hardCap, uint256 minPurchaseAmount, uint256 maxPurchasePerUser, uint256 saleStartTime, uint256 saleEndTime)` — configure everything at once (0 = no restriction)
- `setHardCap`, `setMinPurchaseAmount`, `setMaxPurchasePerUser`, `setMaxPurchaseForUser(address user, uint256 max)`, `setSaleTimeWindow`

#### Whitelist & Operations
- `addToWhitelist(address)` / `removeFromWhitelist(address)` — requires `ADMIN_ROLE` or `WHITELIST_ROLE`
- `updateWhitelistRequirement(bool)` — enable/disable the whitelist requirement
- `updatePaymentRecipient(address)` — change where payments are forwarded
- `pause()` / `unpause()` — halt/resume purchases
- `emergencyWithdraw(address token, address recipient, uint256 amount)` — recover ETH/tokens accidentally sent to the contract (the contract holds no funds during normal operation)

## 🔐 Roles

| Role | Description |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Can grant/revoke all roles |
| `ADMIN_ROLE` | Manages payment tokens, rates, oracles, limits, whitelist, pausing, and withdrawals |
| `WHITELIST_ROLE` | Can add/remove whitelist entries only |
| ProxyAdmin owner | Can upgrade the implementation (set at deployment, outside AccessControl) |

> **Production requirement:** hold the admin and ProxyAdmin-owner keys in a multisig, ideally behind a timelock. See [Security Considerations](#%EF%B8%8F-security-considerations).

## 📝 Setup Process

### 1. Deploy

Deploy via the Foundry script (`script/DeployTokenSale.s.sol`) or the Node.js path ([DEPLOY_NODEJS.md](./DEPLOY_NODEJS.md)). Both deploy the implementation and a transparent proxy, and initialize atomically.

### 2. Grant MINTER_ROLE

The TokenSale proxy must be able to mint the base token:

```solidity
bytes32 MINTER_ROLE = keccak256("MINTER_ROLE");
baseToken.grantRole(MINTER_ROLE, tokenSaleProxyAddress);
```

### 3. Add Payment Tokens

```solidity
// 1 USDC (6 decimals) = 100 BASE tokens (18 decimals)
tokenSale.addPaymentToken(usdcAddress, 100 * 10**18, 6);

// 1 ETH = 1000 BASE tokens
tokenSale.addPaymentToken(address(0), 1000 * 10**18, 18);
```

### 4. (Optional) Configure Oracle Pricing

All oracle-derived rates are anchored to a base payment token. Every feed must quote against the same currency (e.g. USD):

```solidity
// Anchor: 1 token = 1 EUR (EURc is an allowed payment token)
tokenSale.setBaseRate(eurTokenAddress, 1 * 10**18);

// Feeds — thresholds should match each feed's heartbeat
tokenSale.configureOracle(eurTokenAddress, EUR_USD_FEED, 24 hours);
tokenSale.configureOracle(address(0), ETH_USD_FEED, 1 hours);

// Recommended: sanity bounds in feed decimals
tokenSale.setOraclePriceBounds(address(0), 500e8, 50000e8);

// Required on L2s (Arbitrum/Optimism/Base)
tokenSale.setSequencerUptimeFeed(SEQUENCER_UPTIME_FEED, 1 hours);
```

If ETH/USD = 3000 and EUR/USD = 1.10, one ETH buys `3000 / 1.10 ≈ 2727` tokens. See [ORACLE_FEEDS_README.md](./ORACLE_FEEDS_README.md) for feed addresses.

### 5. (Optional) Sale Limits & Whitelist

```solidity
tokenSale.configureSale(hardCap, minPurchase, maxPerUser, startTime, endTime);

tokenSale.updateWhitelistRequirement(true);
tokenSale.addToWhitelist(userAddress);
```

## 💡 Example Usage

```solidity
// Quote first, then purchase with slippage protection
uint256 paymentAmount = 1000 * 10**6; // 1000 USDC
uint256 minOut = tokenSale.calculateTokens(usdcAddress, paymentAmount);

usdc.approve(tokenSaleAddress, paymentAmount);
uint256 tokens = tokenSale.purchaseWithToken(usdcAddress, paymentAmount, minOut, bytes32(0));

// Purchase with ETH
uint256 minOutEth = tokenSale.calculateTokens(address(0), 1 ether);
uint256 tokensEth = tokenSale.purchaseWithETH{value: 1 ether}(minOutEth, bytes32(0));
```

See [CAST_COMMANDS.md](./CAST_COMMANDS.md) for the complete `cast` command reference.

## 📊 Rate Calculation

The rate is stored as **base tokens (18 decimals) per 1 whole unit of payment token**:

```
baseTokens = (paymentAmount * rate) / (10^paymentTokenDecimals)
```

**USDC (6 decimals):** rate `100 * 10^18` → paying `1000 * 10^6` yields `(1000e6 * 100e18) / 1e6 = 100,000e18` base tokens.

**ETH (18 decimals):** rate `1000 * 10^18` → paying `1e18` yields `(1e18 * 1000e18) / 1e18 = 1000e18` base tokens.

In oracle mode the rate is derived instead: `rate = baseRate * paymentTokenPrice / basePaymentTokenPrice`, with both prices normalized to 18 decimals.

## 🔄 Upgradeability

The contract uses OpenZeppelin's transparent proxy pattern:

- **Proxy address** stays constant — this is the address users and integrations use
- **Implementation** can be replaced by the ProxyAdmin owner
- **State** lives in the proxy and persists across upgrades
- Reentrancy protection uses transient storage (`ReentrancyGuardTransient`) and OpenZeppelin's other parents use ERC-7201 namespaced storage, minimizing storage-layout risk; new state variables must still only ever be **appended**
- The test suite runs OpenZeppelin's upgrade-safety validation on every deployment

## ⚠️ Security Considerations

- **Reentrancy Protection** — all purchase functions are `nonReentrant` (OpenZeppelin `ReentrancyGuardTransient`, requires Cancun/EIP-1153) and follow checks-effects-interactions
- **Access Control** — admin functions gated by roles; whitelist management separable via `WHITELIST_ROLE`
- **Fail-Closed Oracles** — if oracle mode is on and the price is stale, invalid, out of bounds, or the L2 sequencer is down, purchases revert; there is no silent fallback to a manual rate. To sell at the manual rate the admin must explicitly call `setOracleMode(token, false)`
- **Oracle Hardening** — per-feed staleness thresholds, optional min/max price bounds against pinned Chainlink aggregator circuit breakers, optional sequencer uptime check
- **Slippage Protection** — buyers pass `minTokensOut`; purchases revert if the rate moved against them
- **Per-User Limits** — enforced against `totalPurchased` (tokens bought through the sale), so they cannot be bypassed by moving tokens to another wallet nor griefed by unsolicited transfers
- **Order IDs** — scoped per buyer, so a third party cannot front-run and burn someone else's orderId
- **Input Validation** — payment token decimals verified against the token contract; ETH fixed at 18 decimals
- **SafeERC20** everywhere; payments forwarded immediately, the contract holds no funds

### Operational requirements

- **Use a multisig (ideally with a timelock) for the admin and the ProxyAdmin owner.** The admin can change rates, redirect payments, withdraw stray funds, and upgrade the implementation — a single compromised EOA compromises the entire sale.
- **Off-chain order reconciliation** must verify the buyer address and amounts from the `TokensPurchased` event, never the orderId alone.
- **Do not allow fee-on-transfer or rebasing tokens as payment tokens** — buyers would be credited the nominal amount while the recipient receives less.
- **Hard cap** is measured against the base token's `totalSupply()`: tokens minted elsewhere consume the cap, and burns free it up.
- **Keep manual rates current even in oracle mode** — they take effect the moment oracle mode is disabled.

To report a vulnerability, see [SECURITY.md](./SECURITY.md).

## 🧪 Testing

```bash
npm run test              # 106 deterministic unit tests (Foundry)
npm run test:oraclefeeds  # live Chainlink feed checks on a Sepolia fork
```

The unit suite covers purchases, all admin flows, access control on every privileged function, sale limits, oracle pricing (staleness, bounds, sequencer, failure modes), slippage, order-ID semantics, and the upgrade-safety validation.

## 📚 Documentation

- [CAST_COMMANDS.md](./CAST_COMMANDS.md) — full `cast` command reference for every contract function
- [DEPLOY_NODEJS.md](./DEPLOY_NODEJS.md) — Node.js/ethers deployment guide
- [ORACLE_FEEDS_README.md](./ORACLE_FEEDS_README.md) — Chainlink feed selection and fork tests
- `npm run docgen` — generate API documentation from NatSpec into `docs/`

## 📄 License

[MIT](./LICENSE)
