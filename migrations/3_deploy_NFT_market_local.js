const BigNumber = web3.utils.BN;

//ARTIFACTS
const Marketplace = artifacts.require('MarketplaceTest')
const Volcie = artifacts.require('VolcieToken')
const KittieFightToken = artifacts.require("KittieFightToken");
const LegacyERC721 = artifacts.require("MockERC721Token")

//Rinkeby address of KittieFightToken
//const KTY_ADDRESS = '0x8d05f69bd9e804eb467c7e1f2902ecd5e41a72da';

const ERC20_TOKEN_SUPPLY = new BigNumber(
  web3.utils.toWei("100000000", "ether") //100 Million
);

module.exports = (deployer, network, accounts) => {
  deployer
    .deploy(Volcie)
    .then(() => deployer.deploy(KittieFightToken, ERC20_TOKEN_SUPPLY))
    .then(() => deployer.deploy(LegacyERC721))
    .then(() => deployer.deploy(Marketplace, KittieFightToken.address, LegacyERC721.address, accounts[0]))  
    .then(async () => {
      console.log("\nGetting contract instances...");

      // TOKENS
      volcie = await Volcie.deployed()
      console.log("Volcie:", volcie.address);
      legacyERC721 = await LegacyERC721.deployed();
      kittieFightToken = await KittieFightToken.deployed();
      console.log('KTY:',kittieFightToken.address);
      //kittieFightToken = await KittieFightToken.at(KTY_ADDRESS);
      //console.log(kittieFightToken.address)

      // Marketplace
      marketplace = await Marketplace.deployed();
      console.log("Marketplace:", marketplace.address)
    });
};
