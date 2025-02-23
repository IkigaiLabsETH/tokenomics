import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  // Deploy Token
  const token = await deploy('IkigaiToken', {
    from: deployer,
    args: [],
    log: true,
  });

  // Deploy NFT
  const nft = await deploy('IkigaiNFT', {
    from: deployer,
    args: [],
    log: true,
  });

  // Deploy Rewards
  const rewards = await deploy('IkigaiRewards', {
    from: deployer,
    args: [token.address, nft.address],
    log: true,
  });

  // Deploy Treasury
  const treasury = await deploy('IkigaiTreasury', {
    from: deployer,
    args: [token.address],
    log: true,
  });

  // Deploy Marketplace
  const marketplace = await deploy('IkigaiMarketplace', {
    from: deployer,
    args: [nft.address, token.address, treasury.address],
    log: true,
  });
};

export default func;
func.tags = ['Core']; 