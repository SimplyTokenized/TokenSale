# Node.js Deployment Guide for TokenSale Contract

This guide explains how to compile and deploy the TokenSale contract and its TransparentUpgradeableProxy using Node.js, solc, and ethers.js.

## Prerequisites

1. **Node.js** (v18 or higher)
2. **npm** or **yarn**
3. **Ethereum RPC endpoint** (local node, Infura, Alchemy, etc.)
4. **Deployer account** with sufficient ETH for gas fees

## Installation

1. Install Node.js dependencies:

```bash
npm install
```

This will install:
- `dotenv` - Loads environment variables from .env file
- `ethers` - Ethereum library for interacting with the blockchain
- `solc` - Solidity compiler

## Configuration

Set the following environment variables before running the deployment script:

```bash
export RPC_URL="http://localhost:8545"  # Your Ethereum RPC URL
export PRIVATE_KEY="0x..."                # Private key of deployer account (without 0x prefix is also OK)
export BASE_TOKEN="0x..."                 # Address of the base token contract
export PAYMENT_RECIPIENT="0x..."          # Address that receives payments
export ADMIN="0x..."                      # Admin address for the TokenSale contract
```

Or create a `.env` file in the TokenSale directory:

```env
RPC_URL=http://localhost:8545
PRIVATE_KEY=your_private_key_here
BASE_TOKEN=0x...
PAYMENT_RECIPIENT=0x...
ADMIN=0x...
```

The script automatically loads the `.env` file - no need to source it manually!

## Usage

### Basic Deployment

Run the deployment script:

```bash
npm run deploy:nodejs
```

Or directly:

```bash
node deploy-nodejs.js
```

### What the Script Does

1. **Compiles TokenSale.sol** - Compiles the TokenSale contract and all its dependencies using solc
2. **Compiles TransparentUpgradeableProxy.sol** - Compiles the OpenZeppelin proxy contract
3. **Deploys Implementation** - Deploys the TokenSale implementation contract
4. **Deploys Proxy** - Deploys the TransparentUpgradeableProxy pointing to the implementation
5. **Initializes Contract** - Calls the `initialize` function through the proxy
6. **Verifies Deployment** - Verifies that the contract was deployed and initialized correctly

### Example Output

```
🚀 TokenSale Deployment Script
================================

📡 Connecting to RPC: http://localhost:8545
👤 Deployer: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
💰 Balance: 10000.0 ETH

📦 Compiling TokenSale...
   Using Solidity version: 0.8.27
   Found 45 source files
   ✅ Compilation successful

📦 Compiling TransparentUpgradeableProxy...
   Using Solidity version: 0.8.22
   Found 12 source files
   ✅ Compilation successful

📤 Deploying TokenSale implementation...
   ✅ TokenSale implementation deployed at: 0x5FbDB2315678afecb367f032d93F642f64180aa3

📤 Deploying TransparentUpgradeableProxy...
   Implementation: 0x5FbDB2315678afecb367f032d93F642f64180aa3
   Admin: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
   Init data length: 196 bytes
   ✅ Proxy deployed at: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512

🔍 Verifying deployment...
   Base Token: 0x...
   Payment Recipient: 0x...
   Admin has DEFAULT_ADMIN_ROLE: true
   ✅ Deployment verified successfully!

==================================================
📋 Deployment Summary
==================================================
Implementation Address: 0x5FbDB2315678afecb367f032d93F642f64180aa3
Proxy Address (USE THIS): 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
Base Token: 0x...
Payment Recipient: 0x...
Admin: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
==================================================

✅ Deployment completed successfully!

💡 Use the proxy address (0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512) to interact with the TokenSale contract.
```

## Important Notes

1. **Use the Proxy Address**: Always use the proxy address (not the implementation address) to interact with the TokenSale contract. The proxy address is the one that should be shared with users and integrated into your frontend.

2. **Admin Account**: The admin account specified in the `ADMIN` environment variable will have full control over the contract, including the ability to upgrade it. Keep this account secure.

3. **Gas Fees**: Make sure your deployer account has sufficient ETH to cover gas fees for:
   - Deploying the TokenSale implementation
   - Deploying the TransparentUpgradeableProxy
   - Initializing the contract

4. **Network**: The script will connect to the network specified in `RPC_URL`. Make sure you're deploying to the correct network.

## Troubleshooting

### Compilation Errors

If you encounter compilation errors:

1. **Missing Dependencies**: Make sure all OpenZeppelin contracts are installed:
   ```bash
   forge install OpenZeppelin/openzeppelin-contracts-upgradeable OpenZeppelin/openzeppelin-foundry-upgrades OpenZeppelin/openzeppelin-contracts
   ```

2. **Solc Version**: The script automatically detects the Solidity version from the pragma statement. If you get version-related errors, ensure you have the correct solc version installed.

### Deployment Errors

1. **Insufficient Balance**: Make sure your deployer account has enough ETH
2. **Invalid RPC URL**: Verify your RPC URL is correct and accessible
3. **Invalid Addresses**: Ensure all addresses (BASE_TOKEN, PAYMENT_RECIPIENT, ADMIN) are valid Ethereum addresses

### Import Resolution Errors

If you see import resolution errors, check that:
- All remappings in `remappings.txt` are correct
- All library files exist in the `lib/` directory
- The file structure matches the expected layout

## Alternative: Using Foundry Compilation

If you prefer to use Foundry's compilation output instead of solc directly, you can:

1. Compile with Foundry first:
   ```bash
   forge build
   ```

2. Then modify the script to read from `out/` directory instead of compiling with solc.

However, this script uses solc directly as requested, which gives you full control over the compilation process.

## Security Considerations

- **Never commit private keys** to version control
- **Use environment variables** or secure key management for private keys
- **Verify contracts** on block explorers after deployment
- **Test thoroughly** on testnets before mainnet deployment
- **Review admin permissions** and consider using a multisig for admin operations

## Next Steps

After deployment:

1. **Verify the contract** on block explorers (Etherscan, Snowtrace, etc.)
2. **Configure payment tokens** using the `addPaymentToken` function
3. **Set up oracles** if using dynamic pricing
4. **Configure sale parameters** (hard cap, time windows, etc.)
5. **Add users to whitelist** if whitelisting is enabled

## Support

For issues or questions:
- Check the main [README.md](./README.md)
- Review the contract source code in `src/TokenSale.sol`
- Check the Foundry deployment script in `script/DeployTokenSale.s.sol` for reference
