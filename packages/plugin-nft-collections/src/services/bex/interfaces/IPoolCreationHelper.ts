import { BigNumberish } from "ethers";

export interface IPoolCreationHelper {
  createAndJoinWeightedPool(
    name: string,
    symbol: string,
    createPoolTokens: string[],
    joinPoolTokens: string[],
    normalizedWeights: BigNumberish[],
    rateProviders: string[],
    swapFeePercentage: BigNumberish,
    amountsIn: BigNumberish[],
    owner: string,
    salt: string
  ): Promise<string>;
  
  createAndJoinStablePool(
    name: string,
    symbol: string,
    createPoolTokens: string[],
    amplificationParameter: BigNumberish,
    rateProviders: string[],
    tokenRateCacheDurations: BigNumberish[],
    exemptFromYieldProtocolFeeFlag: boolean,
    swapFeePercentage: BigNumberish,
    amountsIn: BigNumberish[],
    owner: string,
    salt: string,
    joinWBERAPoolWithBERA: boolean
  ): Promise<string>;
} 