import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { 
  IkigaiToken,
  IkigaiNFT,
  IkigaiRewards,
  IkigaiTreasury,
  IkigaiMarketplace 
} from "../typechain-types";

describe("Ikigai Protocol", function () {
  let token: IkigaiToken;
  let nft: IkigaiNFT;
  let rewards: IkigaiRewards;
  let treasury: IkigaiTreasury;
  let marketplace: IkigaiMarketplace;
  let owner: SignerWithAddress;
  let user: SignerWithAddress;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();

    // Deploy contracts
    const Token = await ethers.getContractFactory("IkigaiToken");
    token = await Token.deploy();
    await token.deployed();

    const NFT = await ethers.getContractFactory("IkigaiNFT");
    nft = await NFT.deploy();
    await nft.deployed();

    const Rewards = await ethers.getContractFactory("IkigaiRewards");
    rewards = await Rewards.deploy(token.address, nft.address);
    await rewards.deployed();

    const Treasury = await ethers.getContractFactory("IkigaiTreasury");
    treasury = await Treasury.deploy(token.address);
    await treasury.deployed();

    const Marketplace = await ethers.getContractFactory("IkigaiMarketplace");
    marketplace = await Marketplace.deploy(nft.address, token.address, treasury.address);
    await marketplace.deployed();
  });

  describe("Integration", function () {
    it("Should set up initial state correctly", async function () {
      expect(await nft.owner()).to.equal(owner.address);
      expect(await token.owner()).to.equal(owner.address);
      expect(await rewards.owner()).to.equal(owner.address);
    });

    // Add more integration tests
  });
}); 