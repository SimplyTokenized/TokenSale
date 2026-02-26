// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title SepoliaOracleFeedsTest
 * @notice Live-feed checks for EUR/USD and USDC/USD on Sepolia.
 */
contract SepoliaOracleFeedsTest is Test {
    // Chainlink Data Feed addresses on Ethereum Sepolia
    address internal constant EUR_USD_FEED = 0x1a81afB8146aeFfCFc5E50e8479e826E7D55b910;
    address internal constant USDC_USD_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;

    function setUp() public {
        // Use env RPC if provided; otherwise fallback to a public Sepolia RPC.
        string memory forkUrl = vm.envOr("ETH_SEPOLIA_RPC", string("https://ethereum-sepolia-rpc.publicnode.com"));
        vm.createSelectFork(forkUrl);
    }

    function test_EurUsdFeedIsLive() public view {
        AggregatorV3Interface eurUsd = AggregatorV3Interface(EUR_USD_FEED);

        assertEq(eurUsd.decimals(), 8, "unexpected EUR/USD feed decimals");
        assertEq(eurUsd.description(), "EUR / USD", "unexpected EUR/USD description");

        (, int256 answer,, uint256 updatedAt,) = eurUsd.latestRoundData();
        assertGt(answer, 0, "EUR/USD answer must be positive");
        assertGt(updatedAt, 0, "EUR/USD updatedAt must be set");
        assertLe(updatedAt, block.timestamp, "EUR/USD updatedAt cannot be in future");
    }

    function test_UsdcUsdFeedIsLive() public view {
        AggregatorV3Interface usdcUsd = AggregatorV3Interface(USDC_USD_FEED);

        assertEq(usdcUsd.decimals(), 8, "unexpected USDC/USD feed decimals");
        assertEq(usdcUsd.description(), "USDC / USD", "unexpected USDC/USD description");

        (, int256 answer,, uint256 updatedAt,) = usdcUsd.latestRoundData();
        assertGt(answer, 0, "USDC/USD answer must be positive");
        assertGt(updatedAt, 0, "USDC/USD updatedAt must be set");
        assertLe(updatedAt, block.timestamp, "USDC/USD updatedAt cannot be in future");
    }

    function test_CanDeriveEurToUsdcPrice() public view {
        AggregatorV3Interface eurUsd = AggregatorV3Interface(EUR_USD_FEED);
        AggregatorV3Interface usdcUsd = AggregatorV3Interface(USDC_USD_FEED);

        (, int256 eurUsdAnswer,, uint256 eurUpdatedAt,) = eurUsd.latestRoundData();
        (, int256 usdcUsdAnswer,, uint256 usdcUpdatedAt,) = usdcUsd.latestRoundData();

        assertGt(eurUsdAnswer, 0, "EUR/USD answer must be positive");
        assertGt(usdcUsdAnswer, 0, "USDC/USD answer must be positive");
        assertGt(eurUpdatedAt, 0, "EUR/USD updatedAt must be set");
        assertGt(usdcUpdatedAt, 0, "USDC/USD updatedAt must be set");

        // Both feeds have 8 decimals, so ratio keeps 8 decimals:
        // eurToUsdc(8dp) = (EUR/USD * 1e8) / (USDC/USD)
        uint256 eurToUsdc = (uint256(eurUsdAnswer) * 1e8) / uint256(usdcUsdAnswer);

        // Sanity range for testnet data: 1 EUR should be roughly around 1 USDC.
        // Range: 0.5 - 2.0 USDC per EUR (with 8 decimals).
        assertGt(eurToUsdc, 5e7, "EUR->USDC too low");
        assertLt(eurToUsdc, 2e8, "EUR->USDC too high");
    }
}
