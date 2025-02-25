import { ethers, BigNumber } from "ethers";
import { IVault, SwapKind, SingleSwap, FundManagement, JoinPoolRequest } from "./interfaces/IVault";
import { IPoolCreationHelper } from "./interfaces/IPoolCreationHelper";

export class BexService {
  private vault: IVault;
  private poolCreationHelper: IPoolCreationHelper;
  private provider: ethers.providers.Provider;
  private signer: ethers.Signer;
  
  constructor(
    vaultAddress: string,
    poolCreationHelperAddress: string,
    providerOrSigner: ethers.providers.Provider | ethers.Signer
  ) {
    this.provider = ethers.Signer.isSigner(providerOrSigner) 
      ? providerOrSigner.provider! 
      : providerOrSigner;
    
    this.signer = ethers.Signer.isSigner(providerOrSigner)
      ? providerOrSigner
      : new ethers.VoidSigner("0x0000000000000000000000000000000000000000", this.provider);
    
    const vaultAbi = [
      "function swap(tuple(bytes32 poolId, uint8 kind, address assetIn, address assetOut, uint256 amount, bytes userData) singleSwap, tuple(address sender, bool fromInternalBalance, address payable recipient, bool toInternalBalance) funds, uint256 limit, uint256 deadline) external payable returns (uint256)",
      "function joinPool(bytes32 poolId, address sender, address recipient, tuple(address[] assets, uint256[] maxAmountsIn, bytes userData, bool fromInternalBalance) request) external payable",
      "function setRelayerApproval(address user, address relayer, bool approved) external"
    ];
    
    const poolCreationHelperAbi = [
      "function createAndJoinWeightedPool(string name, string symbol, address[] createPoolTokens, address[] joinPoolTokens, uint256[] normalizedWeights, address[] rateProviders, uint256 swapFeePercentage, uint256[] amountsIn, address owner, bytes32 salt) payable returns (address pool)",
      "function createAndJoinStablePool(string name, string symbol, address[] createPoolTokens, uint256 amplificationParameter, address[] rateProviders, uint256[] tokenRateCacheDurations, bool exemptFromYieldProtocolFeeFlag, uint256 swapFeePercentage, uint256[] amountsIn, address owner, bytes32 salt, bool joinWBERAPoolWithBERA) payable returns (address pool)"
    ];
    
    this.vault = new ethers.Contract(vaultAddress, vaultAbi, this.signer) as unknown as IVault;
    this.poolCreationHelper = new ethers.Contract(poolCreationHelperAddress, poolCreationHelperAbi, this.signer) as unknown as IPoolCreationHelper;
  }
  
  async swap(
    poolId: string,
    tokenIn: string,
    tokenOut: string,
    amountIn: BigNumber,
    minAmountOut: BigNumber,
    deadline: number = Math.floor(Date.now() / 1000) + 600 // 10 minutes
  ): Promise<ethers.ContractTransaction> {
    const singleSwap: SingleSwap = {
      poolId,
      kind: SwapKind.GIVEN_IN,
      assetIn: tokenIn,
      assetOut: tokenOut,
      amount: amountIn,
      userData: "0x"
    };
    
    const funds: FundManagement = {
      sender: await this.signer.getAddress(),
      fromInternalBalance: false,
      recipient: await this.signer.getAddress(),
      toInternalBalance: false
    };
    
    return this.vault.swap(singleSwap, funds, minAmountOut, deadline);
  }
  
  async addLiquidity(
    poolId: string,
    tokens: string[],
    amounts: BigNumber[],
    minBptOut: BigNumber
  ): Promise<ethers.ContractTransaction> {
    // Encode userData for joining the pool (EXACT_TOKENS_IN_FOR_BPT_OUT)
    const userData = ethers.utils.defaultAbiCoder.encode(
      ['uint8', 'uint256[]', 'uint256'],
      [1, amounts, minBptOut]
    );
    
    const request: JoinPoolRequest = {
      assets: tokens,
      maxAmountsIn: amounts,
      userData,
      fromInternalBalance: false
    };
    
    return this.vault.joinPool(
      poolId,
      await this.signer.getAddress(),
      await this.signer.getAddress(),
      request
    );
  }
  
  async createWeightedPool(
    name: string,
    symbol: string,
    tokens: string[],
    weights: BigNumber[],
    swapFee: BigNumber,
    initialAmounts: BigNumber[]
  ): Promise<string> {
    // First approve the pool creation helper as a relayer
    await this.vault.setRelayerApproval(
      await this.signer.getAddress(),
      this.poolCreationHelper.address,
      true
    );
    
    // Generate a random salt
    const salt = ethers.utils.hexlify(ethers.utils.randomBytes(32));
    
    // Create empty rate providers array (no rate providers)
    const rateProviders = tokens.map(() => ethers.constants.AddressZero);
    
    // Create and join the pool
    return this.poolCreationHelper.createAndJoinWeightedPool(
      name,
      symbol,
      tokens,
      tokens,
      weights,
      rateProviders,
      swapFee,
      initialAmounts,
      await this.signer.getAddress(),
      salt
    );
  }
} 