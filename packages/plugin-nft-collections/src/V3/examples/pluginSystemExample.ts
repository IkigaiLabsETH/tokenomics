import { ethers } from "ethers";
import { PluginManager } from "../services/PluginManager";
import { BexPlugin } from "../berachain/plugins/BexPlugin";
import { BEX_CONSTANTS } from "../berachain/constants/bex";

async function main() {
  // Setup provider and signer
  const provider = new ethers.providers.JsonRpcProvider("https://rpc.berachain.com");
  const privateKey = process.env.PRIVATE_KEY!;
  const signer = new ethers.Wallet(privateKey, provider);
  
  // Create plugin manager
  const pluginManager = new PluginManager();
  
  // Create and register BEX plugin
  const bexPlugin = new BexPlugin(provider, signer);
  const registered = await pluginManager.registerPlugin(bexPlugin);
  
  if (registered) {
    console.log("BEX plugin registered successfully");
    
    // Get BEX integration from the plugin
    const bexPlugin = pluginManager.getPlugin<BexPlugin>("BexPlugin");
    if (bexPlugin && bexPlugin.isInitialized()) {
      const bexIntegration = bexPlugin.getIntegration();
      
      if (bexIntegration) {
        // Use BEX integration
        const NFT_COLLECTION_TOKEN = "0x1234567890123456789012345678901234567890"; // Replace with actual address
        const amountIn = ethers.utils.parseEther("10"); // 10 BERA
        
        try {
          // Swap BERA for NFT collection tokens
          const swapTx = await bexIntegration.swapForNFTPurchase(
            BEX_CONSTANTS.BERA_ADDRESS,
            NFT_COLLECTION_TOKEN,
            amountIn,
            "1" // 1% slippage
          );
          
          console.log("Swap transaction hash:", swapTx.hash);
          await swapTx.wait();
          console.log("Swap completed successfully!");
        } catch (error) {
          console.error("Error:", error);
        }
      }
    }
  }
  
  // Shutdown all plugins when done
  await pluginManager.shutdownAll();
}

main().catch(console.error); 