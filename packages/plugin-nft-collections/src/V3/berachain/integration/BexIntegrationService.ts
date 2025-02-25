import { ethers, BigNumber } from "ethers";
import { BexTradingService } from "../trading/BexTradingService";
import { BEX_CONSTANTS } from "../constants/bex";
import { ERC20__factory } from "../../interfaces/factories/ERC20__factory";
import { NFTCollectionProvider } from "../../providers/NFTCollectionProvider";
import { PositionManager } from "../../services/PositionManager";

export class BexIntegrationService {
  private bexTradingService: BexTradingService;
  private nftCollectionProvider: NFTCollectionProvider;
  private positionManager: PositionManager;
  private signer: ethers.Signer;
  
  constructor(
    signer: ethers.Signer,
    nftCollectionProvider: NFTCollectionProvider,
    positionManager: PositionManager
  ) {
    this.signer = signer;
    this.nftCollectionProvider = nftCollectionProvider;
    this.positionManager = positionManager;
    
    // Initialize BEX trading service
    this.bexTradingService = new BexTradingService(
      BEX_CONSTANTS.VAULT_ADDRESS,
      BEX_CONSTANTS.POOL_CREATION_HELPER_ADDRESS,
      BEX_CONSTANTS.API_BASE_URL,
      BEX_CONSTANTS.CHAIN_ID,
      signer
    );
  }
  
  /**
   * Swap tokens using BEX to acquire funds for NFT purchases
   */
  async swapForNFTPurchase(
    tokenIn: string,
    tokenOut: string,
    amountIn: BigNumber,
    slippagePercentage: string = "1"
  ): Promise<ethers.ContractTransaction> {
    // First approve the token spending if needed
    const tokenContract = ERC20__factory.connect(tokenIn, this.signer);
    const allowance = await tokenContract.allowance(
      await this.signer.getAddress(),
      BEX_CONSTANTS.VAULT_ADDRESS
    );
    
    if (allowance.lt(amountIn)) {
      const approveTx = await tokenContract.approve(
        BEX_CONSTANTS.VAULT_ADDRESS,
        amountIn
      );
      await approveTx.wait();
    }
    
    // Execute the swap
    return this.bexTradingService.executeSwap(
      tokenIn,
      tokenOut,
      amountIn,
      slippagePercentage
    );
  }
  
  /**
   * Swap NFT sale proceeds to desired token
   */
  async swapNFTSaleProceeds(
    tokenIn: string,
    tokenOut: string,
    amountIn: BigNumber,
    slippagePercentage: string = "1"
  ): Promise<ethers.ContractTransaction> {
    return this.swapForNFTPurchase(tokenIn, tokenOut, amountIn, slippagePercentage);
  }
  
  /**
   * Create a liquidity pool for an NFT collection token
   */
  async createLiquidityPoolForCollection(
    collectionAddress: string,
    baseTokenAddress: string, // e.g., BERA
    initialTokenAmount: BigNumber,
    initialBaseAmount: BigNumber,
    swapFeePercentage: number = 0.01 // 1%
  ): Promise<string> {
    // Get collection details
    const collection = await this.nftCollectionProvider.getCollection(collectionAddress);
    
    // Create pool name and symbol
    const name = `${collection.name}-BERA Pool`;
    const symbol = `${collection.symbol}-BERA`;
    
    // Approve tokens for pool creation
    const tokenContract = ERC20__factory.connect(collectionAddress, this.signer);
    const baseTokenContract = ERC20__factory.connect(baseTokenAddress, this.signer);
    
    const approveTx1 = await tokenContract.approve(
      BEX_CONSTANTS.POOL_CREATION_HELPER_ADDRESS,
      initialTokenAmount
    );
    await approveTx1.wait();
    
    const approveTx2 = await baseTokenContract.approve(
      BEX_CONSTANTS.POOL_CREATION_HELPER_ADDRESS,
      initialBaseAmount
    );
    await approveTx2.wait();
    
    // Create the pool
    return this.bexTradingService.createWeightedPool(
      name,
      symbol,
      [collectionAddress, baseTokenAddress],
      [0.5, 0.5], // Equal weights
      swapFeePercentage,
      [initialTokenAmount, initialBaseAmount]
    );
  }
  
  /**
   * Add liquidity to an existing pool for an NFT collection
   */
  async addLiquidityForCollection(
    collectionAddress: string,
    baseTokenAddress: string,
    tokenAmount: BigNumber,
    baseAmount: BigNumber,
    slippagePercentage: string = "1"
  ): Promise<ethers.ContractTransaction | null> {
    // Find the pool
    const poolId = await this.bexTradingService.findPoolForTokens(
      collectionAddress,
      baseTokenAddress
    );
    
    if (!poolId) {
      console.error("No pool found for collection");
      return null;
    }
    
    // Approve tokens for adding liquidity
    const tokenContract = ERC20__factory.connect(collectionAddress, this.signer);
    const baseTokenContract = ERC20__factory.connect(baseTokenAddress, this.signer);
    
    const approveTx1 = await tokenContract.approve(
      BEX_CONSTANTS.VAULT_ADDRESS,
      tokenAmount
    );
    await approveTx1.wait();
    
    const approveTx2 = await baseTokenContract.approve(
      BEX_CONSTANTS.VAULT_ADDRESS,
      baseAmount
    );
    await approveTx2.wait();
    
    // Add liquidity
    return this.bexTradingService.addLiquidityToPool(
      poolId,
      [collectionAddress, baseTokenAddress],
      [tokenAmount, baseAmount],
      slippagePercentage
    );
  }
  
  /**
   * Execute a trade based on position manager signals
   */
  async executePositionTrade(
    positionId: string,
    action: 'enter' | 'exit',
    amount: BigNumber
  ): Promise<ethers.ContractTransaction | null> {
    // Get position details
    const position = await this.positionManager.getPosition(positionId);
    
    if (!position) {
      console.error("Position not found");
      return null;
    }
    
    // Determine tokens for the trade
    const tokenIn = action === 'enter' ? position.baseToken : position.assetToken;
    const tokenOut = action === 'enter' ? position.assetToken : position.baseToken;
    
    // Execute the swap
    return this.swapForNFTPurchase(
      tokenIn,
      tokenOut,
      amount,
      position.slippageTolerance.toString()
    );
  }
  
  /**
   * Check if a token has sufficient liquidity on BEX
   */
  async checkTokenLiquidity(tokenAddress: string): Promise<boolean> {
    try {
      // Find pools containing this token
      const pools = await this.bexTradingService.findPoolForTokens(
        tokenAddress,
        BEX_CONSTANTS.BERA_ADDRESS // Assuming BERA is the main base token
      );
      
      return !!pools; // Return true if pools exist
    } catch (error) {
      console.error("Error checking token liquidity:", error);
      return false;
    }
  }
} 