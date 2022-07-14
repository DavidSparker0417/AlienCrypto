const { dsConfigWrite, dsConfigRead } = require("../ds-lib/ds-config");
const CONFIG_PATH = "./config.json";
const upgrade = require("@openzeppelin/truffle-upgrades");

async function deployAlNft(deployer, network, alToken) {
  const alNft = artifacts.require("AlNft");

  console.log(`+++++++++++ Deploying AlNft to ${network} ++++++++++`);
  const contract = await upgrade.deployProxy(alNft, 
    [
      /*uri*/   "",
      /*token*/ alToken
    ],
    {deployer, initializer: "initialize"});
  console.log("[AlNft] admin address = ", await upgrade.erc1967.getAdminAddress(contract.address));
  console.log("[AlNft] implementation address = ", await upgrade.erc1967.getImplementationAddress(contract.address));
  console.log("[AlNft] proxy address = ", contract.address);
  return contract;
}

module.exports = async function (deployer, network) {
  const config = dsConfigRead(CONFIG_PATH);
  const contract = await deployAlNft(deployer, network, config.networks[network].alToken);
  console.log("AlNft = ", contract.address);
  config.networks[network].alNft = contract.address;
  dsConfigWrite(config, CONFIG_PATH);
};
