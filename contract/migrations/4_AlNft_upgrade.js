const CONFIG_PATH = "./config.json";
const argv = require("minimist")(process.argv.slice(2), {string: ["old-address"]});
const { dsConfigWrite, dsConfigRead } = require("../ds-lib/ds-config");
const upgrade = require("@openzeppelin/truffle-upgrades");
const alNft = artifacts.require("AlNft");

module.exports = async function (deployer, network) {
  let oldAddr = argv["old-address"];
  if (!oldAddr) oldAddr = (await alNft.deployed()).address;
  if (!oldAddr) return;

  const config = dsConfigRead(CONFIG_PATH);

  console.log(`++++++++++++++ Upgrading old AlNft(${oldAddr}) on ${network} +++++++++++++`);
  const contract = await upgrade.upgradeProxy(oldAddr, alNft, 
    {
      deployer, 
      // call: {
      //   fn : "init",
      //   args: [
      //     config.networks[network].alToken
      //   ],
      // }
    });
  console.log("admin = ", await upgrade.erc1967.getAdminAddress(contract.address));
  console.log("implementation = ", await upgrade.erc1967.getImplementationAddress(contract.address));
  console.log("proxy = ", contract.address);

  config.networks[network].alNft = contract.address;
  dsConfigWrite(config, CONFIG_PATH);
}