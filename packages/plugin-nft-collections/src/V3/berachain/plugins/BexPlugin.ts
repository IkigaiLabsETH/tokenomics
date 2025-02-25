import { ethers } from "ethers";
import { BexIntegrationService } from "../integration/BexIntegrationService";
import { BexIntegrationFactory } from "../integration/BexIntegrationFactory";
import { PluginInterface } from "../../interfaces/PluginInterface";

export class BexPlugin implements PluginInterface {
  private bexIntegration: BexIntegrationService | null = null;
  private provider: ethers.providers.Provider;
  private signer: ethers.Signer;
  
  constructor(provider: ethers.providers.Provider, signer: ethers.Signer) {
    this.provider = provider;
    this.signer = signer;
  }
  
  async initialize(): Promise<boolean> {
    try {
      // Check if BEX is available
      const isAvailable = await BexIntegrationFactory.isAvailable(this.provider);
      if (!isAvailable) {
        console.log("BEX is not available on this network");
        return false;
      }
      
      // Create BEX integration
      this.bexIntegration = await BexIntegrationFactory.create(this.provider, this.signer);
      return true;
    } catch (error) {
      console.error("Failed to initialize BEX plugin:", error);
      return false;
    }
  }
  
  async shutdown(): Promise<void> {
    // Clean up any resources if needed
    this.bexIntegration = null;
  }
  
  getName(): string {
    return "BexPlugin";
  }
  
  getVersion(): string {
    return "1.0.0";
  }
  
  getIntegration(): BexIntegrationService | null {
    return this.bexIntegration;
  }
  
  isInitialized(): boolean {
    return this.bexIntegration !== null;
  }
} 