# Oracle Feeds (Sepolia) for TokenSale

This guide explains which Chainlink oracle contracts to use for `EUR/EURc -> USDC` pricing in `TokenSale`, and how to run the dedicated testcase.

## Why this matters

`TokenSale` expects Chainlink **Data Feeds** that implement `AggregatorV3Interface` (for example: `decimals()`, `description()`, and `latestRoundData()`).

The address below is **not** a price feed:

- `0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD`

It is a Chainlink **Any API Operator** contract (Direct Request workflow), so it should not be used in `configureOracle(...)` for price feed pricing.

## Correct Sepolia price feeds

Use these Chainlink Data Feeds on Ethereum Sepolia:

- `EUR / USD`: `0x1a81afB8146aeFfCFc5E50e8479e826E7D55b910`
- `USDC / USD`: `0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E`

### How pricing is derived

For `base = EUR/EURc` and investment in `USDC`, the contract can derive:

- `USDC per EUR` (or inverse) from `EUR/USD` and `USDC/USD`
- Formula concept: `EUR->USDC = (EUR/USD) / (USDC/USD)` (after handling feed decimals)

In `TokenSale`, you configure:

1. Base token oracle mapping for EUR/EURc with `EUR/USD`
2. Payment token oracle mapping for USDC with `USDC/USD`
3. Base rate via `setBaseRate(...)`

## Dedicated oracle testcase

Test file:

- `test/SepoliaOracleFeeds.t.sol`

What it validates:

- Feed interface is available
- Feed metadata (`description`, `decimals`) is correct
- `latestRoundData()` returns valid positive data
- EUR->USDC ratio can be derived with sane bounds

## Run only this oracle test

Use the npm script:

```bash
npm run test:oraclefeeds
```

## Useful Chainlink docs

- Any API testnet operator list (shows `0x6090...` as Operator):  
  https://docs.chain.link/any-api/testnet-oracles
- Data Feeds overview:  
  https://docs.chain.link/data-feeds
- Feed addresses (official registry):  
  https://docs.chain.link/data-feeds/price-feeds/addresses

