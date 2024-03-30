const hre = require('hardhat');
const { getConfigPath } = require('../private/_helpers');
const { getIbcApp } = require('../private/_vibc-helpers.js');
const {setupIbcPacketEventListener} = require("../private/_events");

async function bridge() {
    const accounts = await hre.ethers.getSigners();
    const config = require(getConfigPath());
    const sendConfig = config.sendPacket;

    const networkName = hre.network.name;
    // Get the contract type from the config and get the contract
    const ibcApp = await getIbcApp(networkName);

    // Do logic to prepare the packet
    const channelId = sendConfig[`${networkName}`]["channelId"];
    const channelIdBytes = hre.ethers.encodeBytes32String(channelId);
    const timeoutSeconds = sendConfig[`${networkName}`]["timeout"];

    // Send the packet
    await ibcApp.connect(accounts[0]).bridge(
        channelIdBytes,
        timeoutSeconds,
        Number(hre.network.config.chainId) === 84532 ? 11155420 : 84532,
        {
            value: hre.ethers.parseEther('0.00001')
        }
    );
}

async function main() {
    try {
        await setupIbcPacketEventListener();
        await bridge();
    } catch (error) {
        console.error("❌ Error sending packet: ", error);
        process.exit(1);
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
