export const BEX_CONSTANTS = {
  VAULT_ADDRESS: "0x1234567890123456789012345678901234567890", // Replace with actual address
  POOL_CREATION_HELPER_ADDRESS: "0x0987654321098765432109876543210987654321", // Replace with actual address
  API_BASE_URL: "https://api.berachain.com",
  CHAIN_ID: 80094, // Berachain ID
  
  // Common tokens on Berachain
  BERA_ADDRESS: "0xberaberaberaberaberaberaberabera00000000", // Replace with actual BERA address
  HONEY_ADDRESS: "0xhoneyhoneyhoneyhoneyhoneyhoneyhoney0000", // Replace with actual HONEY address
  USDC_ADDRESS: "0xusdcusdcusdcusdcusdcusdcusdcusdc00000000", // Replace with actual USDC address
  
  // Default pool settings
  DEFAULT_SWAP_FEE: 0.003, // 0.3%
  DEFAULT_SLIPPAGE: "1", // 1%
  
  // Gas settings for Berachain
  GAS_LIMIT_MULTIPLIER: 1.2, // Add 20% to estimated gas
  GAS_PRICE_MULTIPLIER: 1.1, // Add 10% to gas price
};

export const SAFETY_LIMITS = {
  MAX_POSITION_SIZE: 0.1,  // 10% of portfolio
  MAX_SLIPPAGE: 0.05,     // 5% slippage
  MIN_LIQUIDITY: 1000,    // $1000 minimum liquidity
  MAX_PRICE_IMPACT: 0.03, // 3% price impact
  STOP_LOSS: 0.15,        // 15% stop loss
}; 