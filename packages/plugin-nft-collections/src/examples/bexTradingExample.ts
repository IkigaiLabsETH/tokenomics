import { ethers } from "ethers";
import { BexTradingService } from "../services/trading/BexTradingService";
import { BEX_CONSTANTS } from "../constants/bex";

async function main() {
  // Setup provider and signer
  const provider = new ethers.providers.JsonRpcProvider("https://rpc.berachain.com");
  const privateKey = process.env.PRIVATE_KEY!;
  const signer = new ethers.Wallet(privateKey, provider);
  
  // Initialize BEX trading service
  const bexTradingService = new BexTradingService(
    BEX_CONSTANTS.VAULT_ADDRESS,
    BEX_CONSTANTS.POOL_CREATION_HELPER_ADDRESS,
    BEX_CONSTANTS.API_BASE_URL,
    BEX_CONSTANTS.CHAIN_ID,
    signer
  );
  
  // Example: Swap 1 HONEY for BERA
  const HONEY_ADDRESS = "0x1234567890123456789012345678901234567890"; // Replace with actual address
  const BERA_ADDRESS = "0x0987654321098765432109876543210987654321"; // Replace with actual address
  
  const amountIn = ethers.utils.parseEther("1"); // 1 HONEY
  
  try {
    // Execute swap
    const tx = await bexTradingService.executeSwap(
      HONEY_ADDRESS,
      BERA_ADDRESS,
      amountIn,
      "1" // 1% slippage
    );
    
    console.log("Swap transaction hash:", tx.hash);
    await tx.wait();
    console.log("Swap completed successfully!");
    
    // Find a pool for HONEY and BERA
    const poolId = await bexTradingService.findPoolForTokens(HONEY_ADDRESS, BERA_ADDRESS);
    
    if (poolId) {
      console.log("Found pool:", poolId);
      
      // Add liquidity to the pool
      const amounts = [
        ethers.utils.parseEther("1"), // 1 HONEY
        ethers.utils.parseEther("10") // 10 BERA
      ];
      
      const addLiquidityTx = await bexTradingService.addLiquidityToPool(
        poolId,
        [HONEY_ADDRESS, BERA_ADDRESS],
        amounts,
        "1" // 1% slippage
      );
      
      console.log("Add liquidity transaction hash:", addLiquidityTx.hash);
      await addLiquidityTx.wait();
      console.log("Liquidity added successfully!");
    } else {
      console.log("No pool found, creating a new pool...");
      
      // Create a new weighted pool
      const poolAddress = await bexTradingService.createWeightedPool(
        "HONEY-BERA Pool",
        "HONEY-BERA",
        [HONEY_ADDRESS, BERA_ADDRESS],
        [0.5, 0.5], // Equal weights
        0.01, // 1% swap fee
        [
          ethers.utils.parseEther("1"), // 1 HONEY
          ethers.utils.parseEther("10") // 10 BERA
        ]
      );
      
      console.log("Created new pool at address:", poolAddress);
    }
  } catch (error) {
    console.error("Error:", error);
  }
}

main().catch(console.error); 