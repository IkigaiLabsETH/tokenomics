import { ethers, BigNumber } from "ethers";
import { BexService } from "../bex/BexService";
import { BexApiClient, SwapKind } from "../bex/BexApiClient";
import { SAFETY_LIMITS } from "../../constants";

export class BexTradingService {
  private bexService: BexService;
  private bexApiClient: BexApiClient;
  private signer: ethers.Signer;
  
  constructor(
    vaultAddress: string,
    poolCreationHelperAddress: string,
    apiBaseUrl: string,
    chainId: number,
    signer: ethers.Signer
  ) {
    this.signer = signer;
    this.bexService = new BexService(vaultAddress, poolCreationHelperAddress, signer);
    this.bexApiClient = new BexApiClient(apiBaseUrl, chainId);
  }
  
  async executeSwap(
    tokenIn: string,
    tokenOut: string,
    amountIn: BigNumber,
    slippagePercentage: string = "1"
  ): Promise<ethers.ContractTransaction> {
    // Validate the swap against safety limits
    if (amountIn.gt(SAFETY_LIMITS.MAX_POSITION_SIZE)) {
      throw new Error(`Swap amount exceeds maximum position size: ${SAFETY_LIMITS.MAX_POSITION_SIZE}`);
    }
    
    // Fetch optimal swap paths using the SOR
    const swapRoute = await this.bexApiClient.fetchSwapPaths(
      tokenIn,
      tokenOut,
      amountIn,
      SwapKind.GIVEN_IN
    );
    
    // Calculate minimum amount out based on slippage
    const slippageBps = parseFloat(slippagePercentage) * 100;
    const minAmountOut = BigNumber.from(swapRoute.returnAmount)
      .mul(10000 - slippageBps)
      .div(10000);
    
    // Build the swap transaction
    const sender = await this.signer.getAddress();
    const txData = await this.bexApiClient.buildSwapTransaction(
      swapRoute,
      sender,
      sender,
      slippagePercentage
    );
    
    // Execute the transaction
    return this.signer.sendTransaction({
      to: txData.to,
      data: txData.callData,
      value: txData.value
    });
  }
  
  async findPoolForTokens(
    tokenA: string,
    tokenB: string
  ): Promise<string | null> {
    const pools = await this.bexApiClient.queryPools([tokenA, tokenB]);
    
    if (pools.length === 0) {
      return null;
    }
    
    // Return the first pool ID
    return pools[0].id;
  }
  
  async addLiquidityToPool(
    poolId: string,
    tokens: string[],
    amounts: BigNumber[],
    slippagePercentage: string = "1"
  ): Promise<ethers.ContractTransaction> {
    // Calculate minimum BPT out based on slippage
    // This is a simplified calculation - in a real implementation,
    // you would query the expected BPT out first
    const minBptOut = BigNumber.from(0); // Replace with actual calculation
    
    return this.bexService.addLiquidity(poolId, tokens, amounts, minBptOut);
  }
  
  async createWeightedPool(
    name: string,
    symbol: string,
    tokens: string[],
    weights: number[],
    swapFeePercentage: number,
    initialAmounts: BigNumber[]
  ): Promise<string> {
    // Convert weights to normalized weights (must sum to 1e18)
    const totalWeight = weights.reduce((a, b) => a + b, 0);
    const normalizedWeights = weights.map(weight => 
      BigNumber.from(Math.floor((weight / totalWeight) * 1e18))
    );
    
    // Convert swap fee percentage to the expected format (e.g., 1% = 0.01e18)
    const swapFee = BigNumber.from(Math.floor(swapFeePercentage * 1e16));
    
    return this.bexService.createWeightedPool(
      name,
      symbol,
      tokens,
      normalizedWeights,
      swapFee,
      initialAmounts
    );
  }
} 