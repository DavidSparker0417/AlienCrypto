const CONFIG_PATH = "./config.json";
const upgrade = require("@openzeppelin/truffle-upgrades");
const { dsConfigRead, dsConfigWrite } = require("../ds-lib/ds-config");

async function deployAlienToken(deployer) {
  const AlienToken = artifacts.require("BuyBackToken");
  await deployer.deploy(AlienToken, 
    "ALIEN",
    "ALN",
    18,
    "1000000000000000000000000000", // 1 billion
    30, // tax fee
    60, // buyback fee
    30, // marketing fee
    "0x85048aae2FCc6877cA379e2dfDD61ea208Fa076C" // marketing wallet
  );
  const contract = await AlienToken.deployed();
}

async function deployAlToken(deployer, network) {
  const alToken = artifacts.require("AlToken");

  console.log(`+++++++++++ Deploying AlToken to ${network} ++++++++++`);
  const contract = await upgrade.deployProxy(alToken, 
    [
      "Alien Token",
      "AlToken",
      18
    ],
    {deployer, initializer: "initialize"});
  console.log("[AlToken] admin address = ", await upgrade.erc1967.getAdminAddress(contract.address));
  console.log("[AlToken] implementation address = ", await upgrade.erc1967.getImplementationAddress(contract.address));
  console.log("[AlToken] proxy address = ", contract.address);
  return contract;
}

module.exports = async function (deployer, network) {
  const config = dsConfigRead(CONFIG_PATH);
  const alTokenContract = await deployAlToken(deployer, network);
  console.log("AlienToken = ", alTokenContract.address);
  config.networks[network].alToken = alTokenContract.address;
  dsConfigWrite(config, CONFIG_PATH);
};
