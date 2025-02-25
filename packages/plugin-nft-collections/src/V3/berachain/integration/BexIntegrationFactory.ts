import { ethers } from "ethers";
import { BexIntegrationService } from "./BexIntegrationService";
import { NFTCollectionProvider } from "../../providers/NFTCollectionProvider";
import { PositionManager } from "../../services/PositionManager";
import { BEX_CONSTANTS } from "../constants/bex";

export class BexIntegrationFactory {
  /**
   * Create a BEX integration service with all required dependencies
   */
  static async create(
    provider: ethers.providers.Provider,
    signerOrPrivateKey: ethers.Signer | string
  ): Promise<BexIntegrationService> {
    // Setup signer
    let signer: ethers.Signer;
    if (typeof signerOrPrivateKey === 'string') {
      signer = new ethers.Wallet(signerOrPrivateKey, provider);
    } else {
      signer = signerOrPrivateKey;
    }
    
    // Create dependencies
    const nftCollectionProvider = new NFTCollectionProvider(provider);
    const positionManager = new PositionManager(provider, signer);
    
    // Create and return the integration service
    return new BexIntegrationService(
      signer,
      nftCollectionProvider,
      positionManager
    );
  }
  
  /**
   * Check if BEX is available on the current network
   */
  static async isAvailable(provider: ethers.providers.Provider): Promise<boolean> {
    try {
      const network = await provider.getNetwork();
      return network.chainId === BEX_CONSTANTS.CHAIN_ID;
    } catch (error) {
      console.error("Error checking BEX availability:", error);
      return false;
    }
  }
} 