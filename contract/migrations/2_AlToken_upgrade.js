const argv = require("minimist")(process.argv.slice(2), {string: ["old-address"]});
const { dsConfigWrite, dsConfigRead } = require("../ds-lib/ds-config");
const upgrade = require("@openzeppelin/truffle-upgrades");
const alToken = artifacts.require("AlToken");
const CONFIG_PATH = "./config.json";

module.exports = async function (deployer, network) {
  let oldAddr = argv["old-address"];
  if (!oldAddr) oldAddr = (await alToken.deployed()).address;
  if (!oldAddr) return;

  console.log(`++++++++++++++ Upgrading old AlToken(${oldAddr}) on ${network} +++++++++++++`);
  const contract = await upgrade.upgradeProxy(oldAddr, alToken, {deployer});
  console.log("admin = ", await upgrade.erc1967.getAdminAddress(contract.address));
  console.log("implementation = ", await upgrade.erc1967.getImplementationAddress(contract.address));
  console.log("proxy = ", contract.address);

  const config = dsConfigRead(CONFIG_PATH);
  config.networks[network].alToken = contract.address;
  dsConfigWrite(config, CONFIG_PATH);
}