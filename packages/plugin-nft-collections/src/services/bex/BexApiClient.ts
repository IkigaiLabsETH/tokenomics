import axios from "axios";
import { BigNumber, ethers } from "ethers";

export enum SwapKind {
  GIVEN_IN = 0,
  GIVEN_OUT = 1
}

export interface TokenAmount {
  address: string;
  amount: string;
}

export interface SwapPath {
  poolId: string;
  tokenIn: string;
  tokenOut: string;
  amount: string;
}

export interface SwapRoute {
  paths: SwapPath[];
  tokenIn: string;
  tokenOut: string;
  swapAmount: string;
  returnAmount: string;
  swapKind: SwapKind;
}

export class BexApiClient {
  private baseUrl: string;
  private chainId: number;
  
  constructor(baseUrl: string, chainId: number) {
    this.baseUrl = baseUrl;
    this.chainId = chainId;
  }
  
  async fetchSwapPaths(
    tokenIn: string,
    tokenOut: string,
    amount: BigNumber,
    swapKind: SwapKind = SwapKind.GIVEN_IN
  ): Promise<SwapRoute> {
    try {
      const response = await axios.get(`${this.baseUrl}/sor/swap/paths`, {
        params: {
          chainId: this.chainId,
          tokenIn,
          tokenOut,
          swapKind,
          swapAmount: amount.toString()
        }
      });
      
      return response.data;
    } catch (error) {
      console.error("Error fetching swap paths:", error);
      throw error;
    }
  }
  
  async buildSwapTransaction(
    swapRoute: SwapRoute,
    sender: string,
    recipient: string,
    slippagePercentage: string = "1",
    deadline: number = Math.floor(Date.now() / 1000) + 600 // 10 minutes
  ): Promise<{to: string; callData: string; value: string}> {
    try {
      const response = await axios.post(`${this.baseUrl}/sor/swap/build`, {
        chainId: this.chainId,
        swapRoute,
        sender,
        recipient,
        slippage: slippagePercentage,
        deadline,
        wethIsEth: false
      });
      
      return response.data;
    } catch (error) {
      console.error("Error building swap transaction:", error);
      throw error;
    }
  }
  
  async queryPools(
    tokens: string[],
    limit: number = 5
  ): Promise<any[]> {
    try {
      const query = `
        {
          pools(
            first: ${limit}
            where: {
              tokensList_contains: ${JSON.stringify(tokens)}
            }
          ) {
            id
            address
            poolType
            poolTypeVersion
            tokensList
            swapFee
          }
        }
      `;
      
      const response = await axios.post(`${this.baseUrl}/subgraph`, {
        query
      });
      
      return response.data.data.pools;
    } catch (error) {
      console.error("Error querying pools:", error);
      throw error;
    }
  }
} 