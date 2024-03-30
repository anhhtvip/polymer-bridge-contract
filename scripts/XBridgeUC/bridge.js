const hre = require('hardhat');
const { getConfigPath } = require('../private/_helpers');
const { getIbcApp } = require('../private/_vibc-helpers.js');
const {setupIbcPacketEventListener} = require("../private/_events");

async function bridge() {
    const accounts = await hre.ethers.getSigners();
    const config = require(getConfigPath());
    const sendConfig = config.sendUniversalPacket;

    const networkName = hre.network.name;
    // Get the contract type from the config and get the contract
    const ibcApp = await getIbcApp(networkName);

    // Do logic to prepare the packet

    // If the network we are sending on is optimism, we need to use the base port address and vice versa
    const destPortAddr = networkName === "optimism" ?
        config["sendUniversalPacket"]["base"]["portAddr"] :
        config["sendUniversalPacket"]["optimism"]["portAddr"];
    const channelId = sendConfig[`${networkName}`]["channelId"];
    const channelIdBytes = hre.ethers.encodeBytes32String(channelId);
    const timeoutSeconds = sendConfig[`${networkName}`]["timeout"];

    // Send the packet
    await ibcApp.connect(accounts[1]).bridge(
        destPortAddr,
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

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
