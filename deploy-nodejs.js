#!/usr/bin/env node

/**
 * Node.js deployment script for TokenSale contract with TransparentUpgradeableProxy
 * 
 * This script:
 * 1. Compiles TokenSale.sol and all dependencies using solc
 * 2. Compiles TransparentUpgradeableProxy.sol and all dependencies using solc
 * 3. Deploys the TokenSale implementation
 * 4. Deploys the TransparentUpgradeableProxy pointing to the implementation
 * 5. Initializes the TokenSale contract through the proxy
 * 
 * Usage:
 *   node deploy-nodejs.js
 * 
 * Environment variables (can be set in .env file or as environment variables):
 *   RPC_URL - Ethereum RPC URL (default: http://localhost:8545)
 *   PRIVATE_KEY - Private key of deployer account
 *   BASE_TOKEN - Address of the base token contract
 *   PAYMENT_RECIPIENT - Address that receives payments
 *   ADMIN - Admin address for the TokenSale contract
 * 
 * The script automatically loads variables from .env file if it exists.
 */

const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');

// Load environment variables from .env file if it exists
try {
  const dotenv = require('dotenv');
  const envPath = path.join(__dirname, '.env');
  if (fs.existsSync(envPath)) {
    dotenv.config({ path: envPath });
    console.log('📄 Loaded environment variables from .env file');
  }
} catch (error) {
  // dotenv is optional, continue without it
  console.log('⚠️  dotenv not available, using environment variables only');
}

// Load solc compiler
let solc;
try {
  solc = require('solc');
} catch (error) {
  console.error('Error: solc package not found. Please install it with: npm install solc');
  process.exit(1);
}

// Configuration
const CONFIG = {
  RPC_URL: process.env.RPC_URL || 'http://localhost:8545',
  PRIVATE_KEY: process.env.PRIVATE_KEY || '',
  BASE_TOKEN: process.env.BASE_TOKEN || '',
  PAYMENT_RECIPIENT: process.env.PAYMENT_RECIPIENT || '',
  ADMIN: process.env.ADMIN || '',
  SOLIDITY_VERSION: '0.8.27',
};

// Remappings from remappings.txt
const REMAPPINGS = {
  'forge-std/': './lib/forge-std/src/',
  '@openzeppelin/contracts/': './lib/openzeppelin-contracts/contracts/',
  '@openzeppelin/contracts-upgradeable/': './lib/openzeppelin-contracts-upgradeable/contracts/',
  '@openzeppelin-foundry-upgrades/': './lib/openzeppelin-foundry-upgrades/src/',
  '@chainlink/contracts/': './lib/chainlink-brownie-contracts/contracts/',
};

/**
 * Resolve import path using remappings
 */
function resolveImport(importPath) {
  for (const [prefix, replacement] of Object.entries(REMAPPINGS)) {
    if (importPath.startsWith(prefix)) {
      const relativePath = importPath.replace(prefix, replacement);
      const fullPath = path.join(__dirname, relativePath);
      if (fs.existsSync(fullPath)) {
        return fullPath;
      }
    }
  }
  // Try direct path
  const directPath = path.join(__dirname, importPath);
  if (fs.existsSync(directPath)) {
    return directPath;
  }
  return null;
}

/**
 * Read a Solidity file and all its dependencies recursively
 */
function readSolidityFile(filePath, visited = new Set()) {
  const normalizedPath = path.resolve(filePath);
  
  if (visited.has(normalizedPath)) {
    return null; // Already processed
  }
  
  if (!fs.existsSync(normalizedPath)) {
    throw new Error(`File not found: ${normalizedPath}`);
  }
  
  visited.add(normalizedPath);
  const content = fs.readFileSync(normalizedPath, 'utf8');
  
  // Extract imports
  const importRegex = /import\s+["']([^"']+)["']/g;
  const imports = [];
  let match;
  
  while ((match = importRegex.exec(content)) !== null) {
    const importPath = match[1];
    const resolvedPath = resolveImport(importPath);
    if (resolvedPath) {
      const depContent = readSolidityFile(resolvedPath, visited);
      if (depContent) {
        imports.push({ path: importPath, content: depContent });
      }
    }
  }
  
  return { path: normalizedPath, content, imports };
}

/**
 * Build sources object for solc compiler
 */
function buildSources(filePath, sources = {}) {
  // Normalize the file path
  const normalizedPath = path.resolve(filePath);
  
  // Check if already processed
  const relativePath = path.relative(__dirname, normalizedPath);
  if (sources[relativePath]) {
    return sources; // Already processed
  }
  
  // Read the file
  if (!fs.existsSync(normalizedPath)) {
    throw new Error(`File not found: ${normalizedPath}`);
  }
  
  const content = fs.readFileSync(normalizedPath, 'utf8');
  sources[relativePath] = { content };
  
  // Extract and process imports
  const importRegex = /import\s+["']([^"']+)["']/g;
  let match;
  const visited = new Set();
  
  while ((match = importRegex.exec(content)) !== null) {
    const importPath = match[1];
    const resolvedPath = resolveImport(importPath);
    if (resolvedPath) {
      const resolvedNormalized = path.resolve(resolvedPath);
      const resolvedRelative = path.relative(__dirname, resolvedNormalized);
      
      // Only process if not already in sources
      if (!sources[resolvedRelative] && !visited.has(resolvedNormalized)) {
        visited.add(resolvedNormalized);
        buildSources(resolvedPath, sources);
      }
    }
  }
  
  return sources;
}

/**
 * Compile contract using solc
 */
function compileContract(contractPath, contractName) {
  console.log(`\n📦 Compiling ${contractName}...`);
  
  // Verify contract file exists
  if (!fs.existsSync(contractPath)) {
    throw new Error(`Contract file not found: ${contractPath}`);
  }
  
  const sources = buildSources(contractPath);
  
  if (Object.keys(sources).length === 0) {
    throw new Error(`No sources found for contract: ${contractPath}`);
  }
  
  // Get the relative path for the main contract
  const contractRelPath = path.relative(__dirname, contractPath);
  
  // Ensure main contract is in sources (read directly if missing)
  if (!sources[contractRelPath]) {
    console.log(`   Warning: Main contract not in sources, reading directly...`);
    const content = fs.readFileSync(contractPath, 'utf8');
    sources[contractRelPath] = { content };
  }
  
  // Create input for solc
  const input = {
    language: 'Solidity',
    sources: {},
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      outputSelection: {
        '*': {
          '*': ['abi', 'evm.bytecode', 'evm.deployedBytecode'],
        },
      },
    },
  };
  
  // Add all sources to input
  for (const [relPath, source] of Object.entries(sources)) {
    input.sources[relPath] = { content: source.content };
  }
  
  // Find compiler version from pragma
  const mainSource = sources[contractRelPath];
  if (!mainSource || !mainSource.content) {
    throw new Error(`Main contract file not found or empty: ${contractPath} (relative: ${contractRelPath})`);
  }
  const pragmaMatch = mainSource.content.match(/pragma\s+solidity\s+([^;]+);/);
  let version = pragmaMatch ? pragmaMatch[1].trim() : CONFIG.SOLIDITY_VERSION;
  
  // Handle version ranges (e.g., ^0.8.22, >=0.8.0 <0.9.0)
  // For simplicity, extract the base version
  const versionMatch = version.match(/(\d+\.\d+\.\d+)/);
  if (versionMatch) {
    version = versionMatch[1];
  } else {
    // Try to extract major.minor
    const versionMatch2 = version.match(/(\d+\.\d+)/);
    if (versionMatch2) {
      version = versionMatch2[1] + '.0';
    }
  }
  
  console.log(`   Using Solidity version: ${version}`);
  console.log(`   Found ${Object.keys(input.sources).length} source files`);
  
  // Create import callback for solc
  function findImports(importPath) {
    const resolved = resolveImport(importPath);
    if (resolved && fs.existsSync(resolved)) {
      const content = fs.readFileSync(resolved, 'utf8');
      return { contents: content };
    }
    return { error: `File not found: ${importPath}` };
  }
  
  // Compile using solc
  let output;
  try {
    if (typeof solc.compile === 'function') {
      // Standard solc package
      output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }));
    } else if (solc.setupMethods) {
      // solc-js with setupMethods (legacy)
      const compiler = solc.setupMethods(solc.loadRemoteVersion || solc.loadVersion);
      output = JSON.parse(compiler.compile(JSON.stringify(input), { import: findImports }));
    } else {
      throw new Error('Unable to initialize solc compiler. Make sure solc package is installed correctly.');
    }
  } catch (error) {
    console.error(`   ❌ Compilation error: ${error.message}`);
    throw error;
  }
  
  if (output.errors) {
    const errors = output.errors.filter(e => e.severity === 'error');
    if (errors.length > 0) {
      console.error('\n❌ Compilation errors:');
      errors.forEach(err => {
        console.error(`   ${err.formattedMessage || err.message}`);
      });
      throw new Error('Compilation failed');
    }
  }
  
  // Find the contract in output
  let contract = null;
  for (const [sourcePath, contracts] of Object.entries(output.contracts)) {
    if (contracts[contractName]) {
      contract = contracts[contractName];
      break;
    }
  }
  
  if (!contract) {
    throw new Error(`Contract ${contractName} not found in compilation output`);
  }
  
  console.log(`   ✅ Compilation successful`);
  return {
    abi: contract.abi,
    bytecode: contract.evm.bytecode.object,
    deployedBytecode: contract.evm.deployedBytecode.object,
  };
}

/**
 * Deploy contract with retry logic for nonce errors
 */
async function deployContract(provider, wallet, abi, bytecode, constructorArgs = [], retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      // Get current nonce to ensure we're using the correct one
      const nonce = await provider.getTransactionCount(await wallet.getAddress(), 'pending');
      if (attempt === 1) {
        console.log(`   Using nonce: ${nonce}`);
      } else {
        console.log(`   Retry attempt ${attempt}/${retries}, using nonce: ${nonce}`);
      }
      
      const factory = new ethers.ContractFactory(abi, bytecode, wallet);
      const contract = await factory.deploy(...constructorArgs);
      
      // Wait for deployment with confirmations
      const txHash = contract.deploymentTransaction()?.hash;
      if (txHash) {
        console.log(`   Transaction hash: ${txHash}`);
      }
      console.log(`   Waiting for confirmation...`);
      
      await contract.waitForDeployment();
      
      // Wait for additional confirmations to ensure transaction is mined
      const receipt = await contract.deploymentTransaction()?.wait(1);
      if (receipt) {
        console.log(`   ✅ Transaction confirmed in block ${receipt.blockNumber}`);
      }
      
      const address = await contract.getAddress();
      return { contract, address };
    } catch (error) {
      // Check if it's a nonce error
      if (error.code === 'NONCE_EXPIRED' || error.code === 'REPLACEMENT_UNDERPRICED' || 
          (error.info && error.info.error && error.info.error.message && 
           error.info.error.message.includes('nonce'))) {
        if (attempt < retries) {
          console.log(`   ⚠️  Nonce error, waiting before retry...`);
          // Wait a bit longer before retrying
          await new Promise(resolve => setTimeout(resolve, 3000));
          continue;
        }
      }
      // If it's not a nonce error or we've exhausted retries, throw
      throw error;
    }
  }
  throw new Error('Deployment failed after retries');
}

/**
 * Main deployment function
 */
async function main() {
  console.log('🚀 TokenSale Deployment Script');
  console.log('================================\n');
  
  // Debug: Show which variables are loaded (without showing sensitive data)
  console.log('📋 Environment variables check:');
  console.log(`   RPC_URL: ${CONFIG.RPC_URL ? '✅ Set' : '❌ Missing'}`);
  console.log(`   PRIVATE_KEY: ${CONFIG.PRIVATE_KEY ? '✅ Set' : '❌ Missing'}`);
  console.log(`   BASE_TOKEN: ${CONFIG.BASE_TOKEN ? '✅ Set' : '❌ Missing'}`);
  console.log(`   PAYMENT_RECIPIENT: ${CONFIG.PAYMENT_RECIPIENT ? '✅ Set' : '❌ Missing'}`);
  console.log(`   ADMIN: ${CONFIG.ADMIN ? '✅ Set' : '❌ Missing'}\n`);
  
  // Validate configuration
  if (!CONFIG.PRIVATE_KEY) {
    throw new Error('PRIVATE_KEY environment variable is required');
  }
  if (!CONFIG.BASE_TOKEN) {
    throw new Error('BASE_TOKEN environment variable is required');
  }
  if (!CONFIG.PAYMENT_RECIPIENT) {
    throw new Error('PAYMENT_RECIPIENT environment variable is required');
  }
  if (!CONFIG.ADMIN) {
    throw new Error('ADMIN environment variable is required');
  }
  
  // Setup provider and wallet
  console.log(`📡 Connecting to RPC: ${CONFIG.RPC_URL}`);
  const provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
  const wallet = new ethers.Wallet(CONFIG.PRIVATE_KEY, provider);
  const deployerAddress = await wallet.getAddress();
  const balance = await provider.getBalance(deployerAddress);
  
  console.log(`👤 Deployer: ${deployerAddress}`);
  console.log(`💰 Balance: ${ethers.formatEther(balance)} ETH\n`);
  
  if (balance === 0n) {
    throw new Error('Deployer account has no balance');
  }
  
  // Compile TokenSale
  const tokenSalePath = path.join(__dirname, 'src', 'TokenSale.sol');
  const tokenSaleCompiled = compileContract(tokenSalePath, 'TokenSale');
  
  // Compile TransparentUpgradeableProxy
  const proxyPath = path.join(__dirname, 'lib', 'openzeppelin-contracts', 'contracts', 'proxy', 'transparent', 'TransparentUpgradeableProxy.sol');
  const proxyCompiled = compileContract(proxyPath, 'TransparentUpgradeableProxy');
  
  // Deploy TokenSale implementation
  console.log('\n📤 Deploying TokenSale implementation...');
  const { address: implementationAddress } = await deployContract(
    provider,
    wallet,
    tokenSaleCompiled.abi,
    tokenSaleCompiled.bytecode
  );
  console.log(`   ✅ TokenSale implementation deployed at: ${implementationAddress}`);
  
  // Wait a bit to ensure the first transaction is fully processed
  // This helps prevent nonce issues when deploying the second contract
  console.log(`   ⏳ Waiting for network to process transaction...`);
  await new Promise(resolve => setTimeout(resolve, 1500));
  
  // Prepare initialization data
  const tokenSaleInterface = new ethers.Interface(tokenSaleCompiled.abi);
  const initData = tokenSaleInterface.encodeFunctionData('initialize', [
    CONFIG.BASE_TOKEN,
    CONFIG.PAYMENT_RECIPIENT,
    CONFIG.ADMIN,
  ]);
  
  // Deploy TransparentUpgradeableProxy
  console.log('\n📤 Deploying TransparentUpgradeableProxy...');
  console.log(`   Implementation: ${implementationAddress}`);
  console.log(`   Admin: ${CONFIG.ADMIN}`);
  console.log(`   Init data length: ${initData.length} bytes`);
  
  // Get the current nonce before deploying proxy to ensure we use the correct one
  const currentNonce = await provider.getTransactionCount(await wallet.getAddress(), 'pending');
  console.log(`   Current account nonce: ${currentNonce}`);
  
  const { address: proxyAddress } = await deployContract(
    provider,
    wallet,
    proxyCompiled.abi,
    proxyCompiled.bytecode,
    [implementationAddress, CONFIG.ADMIN, initData]
  );
  
  console.log(`   ✅ Proxy deployed at: ${proxyAddress}`);
  
  // Verify deployment
  console.log('\n🔍 Verifying deployment...');
  const tokenSale = new ethers.Contract(proxyAddress, tokenSaleCompiled.abi, provider);
  
  try {
    const baseToken = await tokenSale.baseToken();
    const paymentRecipient = await tokenSale.paymentRecipient();
    const adminRole = await tokenSale.DEFAULT_ADMIN_ROLE();
    const hasAdminRole = await tokenSale.hasRole(adminRole, CONFIG.ADMIN);
    
    console.log(`   Base Token: ${baseToken}`);
    console.log(`   Payment Recipient: ${paymentRecipient}`);
    console.log(`   Admin has DEFAULT_ADMIN_ROLE: ${hasAdminRole}`);
    
    if (baseToken.toLowerCase() !== CONFIG.BASE_TOKEN.toLowerCase()) {
      throw new Error('Base token mismatch');
    }
    if (paymentRecipient.toLowerCase() !== CONFIG.PAYMENT_RECIPIENT.toLowerCase()) {
      throw new Error('Payment recipient mismatch');
    }
    if (!hasAdminRole) {
      throw new Error('Admin role not set correctly');
    }
    
    console.log('   ✅ Deployment verified successfully!');
  } catch (error) {
    console.error(`   ⚠️  Verification warning: ${error.message}`);
  }
  
  // Summary
  console.log('\n' + '='.repeat(50));
  console.log('📋 Deployment Summary');
  console.log('='.repeat(50));
  console.log(`Implementation Address: ${implementationAddress}`);
  console.log(`Proxy Address (USE THIS): ${proxyAddress}`);
  console.log(`Base Token: ${CONFIG.BASE_TOKEN}`);
  console.log(`Payment Recipient: ${CONFIG.PAYMENT_RECIPIENT}`);
  console.log(`Admin: ${CONFIG.ADMIN}`);
  console.log('='.repeat(50));
  console.log('\n✅ Deployment completed successfully!');
  console.log(`\n💡 Use the proxy address (${proxyAddress}) to interact with the TokenSale contract.`);
}

// Run the deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('\n❌ Deployment failed:');
    console.error(error);
    process.exit(1);
  });
