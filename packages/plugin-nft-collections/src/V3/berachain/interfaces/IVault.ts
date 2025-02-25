import { BigNumberish } from "ethers";

export enum SwapKind {
  GIVEN_IN = 0,
  GIVEN_OUT = 1
}

export interface SingleSwap {
  poolId: string;
  kind: SwapKind;
  assetIn: string;
  assetOut: string;
  amount: BigNumberish;
  userData: string;
}

export interface FundManagement {
  sender: string;
  fromInternalBalance: boolean;
  recipient: string;
  toInternalBalance: boolean;
}

export interface IVault {
  swap(
    singleSwap: SingleSwap,
    funds: FundManagement,
    limit: BigNumberish,
    deadline: BigNumberish
  ): Promise<BigNumberish>;
  
  joinPool(
    poolId: string,
    sender: string,
    recipient: string,
    request: JoinPoolRequest
  ): Promise<void>;
  
  setRelayerApproval(
    user: string,
    relayer: string,
    approved: boolean
  ): Promise<void>;
}

export interface JoinPoolRequest {
  assets: string[];
  maxAmountsIn: BigNumberish[];
  userData: string;
  fromInternalBalance: boolean;
} 