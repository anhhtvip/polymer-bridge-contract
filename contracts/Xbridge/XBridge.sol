//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "../base/CustomChanIbcApp.sol";

contract XBridge is CustomChanIbcApp {
    enum IbcPacketStatus {
        UNSENT,
        SENT,
        ACKED,
        TIMEOUT
    }

    enum IbcPacketType {
        DEPOSIT,
        BRIDGE
    }

    struct DepositIbcPacket {
        bytes32 id;
        uint256 chainId;
        address sender;
        uint256 amount;
        IbcPacketStatus ibcStatus;
    }

    struct BridgeIbcPacket {
        bytes32 id;
        uint256 fromChainId;
        uint256 toChainId;
        address sender;
        uint256 amount;
        IbcPacketStatus ibcStatus;
    }

    uint256 public chainId;
    mapping(bytes32 => DepositIbcPacket) public depositPackets;
    mapping(bytes32 => BridgeIbcPacket) public bridgePackets;
    mapping(uint256 => uint256) public balances;

    constructor(IbcDispatcher _dispatcher, uint256 _chainId) CustomChanIbcApp(_dispatcher) {
        chainId = _chainId;
    }

    function deposit(
        bytes32 channelId,
        uint64 timeoutSeconds
    ) external payable {
        require(msg.value > 0, "Invalid amount");
        uint256 amount = msg.value;
        balances[chainId] += amount;
        bytes32 id = keccak256(abi.encodePacked(msg.sender, amount, block.timestamp));
        DepositIbcPacket memory ibcPacket = DepositIbcPacket({
            id: id,
            chainId: chainId,
            sender: msg.sender,
            amount: msg.value,
            ibcStatus: IbcPacketStatus.UNSENT
        });
        depositPackets[id] = ibcPacket;
        bytes memory data = abi.encode(IbcPacketType.DEPOSIT, abi.encode(ibcPacket));
        sendPacket(channelId, timeoutSeconds, data);
    }

    function bridge(
        bytes32 channelId,
        uint64 timeoutSeconds,
        uint256 toChainId
    ) external payable {
        require(balances[toChainId] >= msg.value, "Insufficient balance");
        uint256 amount = msg.value;
        balances[chainId] -= amount;
        bytes32 id = keccak256(abi.encodePacked(msg.sender, amount, block.timestamp));
        BridgeIbcPacket memory ibcPacket = BridgeIbcPacket({
            id: id,
            fromChainId: chainId,
            toChainId: toChainId,
            sender: msg.sender,
            amount: amount,
            ibcStatus: IbcPacketStatus.UNSENT
        });
        bridgePackets[id] = ibcPacket;
        bytes memory data = abi.encode(IbcPacketType.BRIDGE, abi.encode(ibcPacket));
        sendPacket(channelId, timeoutSeconds, data);
    }

    // ----------------------- IBC logic  -----------------------
    /**
     * @dev Sends a packet with the caller address over a specified channel.
     * @param channelId The ID of the channel (locally) to send the packet to.
     * @param timeoutSeconds The timeout in seconds (relative).
     */
    function sendPacket(
        bytes32 channelId,
        uint64 timeoutSeconds,
        bytes memory payload
    ) internal {
        // setting the timeout timestamp at 10h from now
        uint64 timeoutTimestamp = uint64(
            (block.timestamp + timeoutSeconds) * 1000000000
        );

        // calling the Dispatcher to send the packet
        dispatcher.sendPacket(channelId, payload, timeoutTimestamp);
    }

    /**
     * @dev Packet lifecycle callback that implements packet receipt logic and returns and acknowledgement packet.
     *      MUST be overriden by the inheriting contract.
     *
     * @param packet the IBC packet encoded by the source and relayed by the relayer.
     */
    function onRecvPacket(
        IbcPacket memory packet
    ) external override onlyIbcDispatcher returns (AckPacket memory ackPacket) {
        recvedPackets.push(packet);
        (IbcPacketType packetType, bytes memory data) = abi.decode(
            packet.data,
            (IbcPacketType, bytes)
        );

        if (packetType == IbcPacketType.DEPOSIT) {
            DepositIbcPacket memory depositPacket = abi.decode(data, (DepositIbcPacket));
            balances[depositPacket.chainId] += depositPacket.amount;
        } else if (packetType == IbcPacketType.BRIDGE) {
            BridgeIbcPacket memory bridgePacket = abi.decode(data, (BridgeIbcPacket));
            balances[bridgePacket.fromChainId] -= bridgePacket.amount;
            balances[bridgePacket.toChainId] += bridgePacket.amount;
            payable(bridgePacket.sender).transfer(bridgePacket.amount);
        } else{
            revert("Invalid packet type");
        }
        return AckPacket(true, packet.data);
    }

    /**
     * @dev Packet lifecycle callback that implements packet acknowledgment logic.
     *      MUST be overriden by the inheriting contract.
     *
     * @param ack the acknowledgment packet encoded by the destination and relayed by the relayer.
     */
    function onAcknowledgementPacket(
        IbcPacket calldata,
        AckPacket calldata ack
    ) external override onlyIbcDispatcher {
        ackPackets.push(ack);
        (IbcPacketType packetType, bytes memory data) = abi.decode(
            ack.data,
            (IbcPacketType, bytes)
        );
        if (packetType == IbcPacketType.DEPOSIT) {
            DepositIbcPacket memory depositPacket = abi.decode(data, (DepositIbcPacket));
            depositPackets[depositPacket.id].ibcStatus = IbcPacketStatus.ACKED;
        } else if (packetType == IbcPacketType.BRIDGE) {
            BridgeIbcPacket memory bridgePacket = abi.decode(data, (BridgeIbcPacket));
            bridgePackets[bridgePacket.id].ibcStatus = IbcPacketStatus.ACKED;
            balances[bridgePacket.fromChainId] += bridgePacket.amount;
        } else {
            revert("Invalid packet type");
        }
    }

    /**
     * @dev Packet lifecycle callback that implements packet receipt logic and return and acknowledgement packet.
     *      MUST be overriden by the inheriting contract.
     *      NOT SUPPORTED YET
     *
     * @param packet the IBC packet encoded by the counterparty and relayed by the relayer
     */
    function onTimeoutPacket(
        IbcPacket calldata packet
    ) external override onlyIbcDispatcher {
        timeoutPackets.push(packet);
        (IbcPacketType packetType, bytes memory data) = abi.decode(
            packet.data,
            (IbcPacketType, bytes)
        );
        if (packetType == IbcPacketType.DEPOSIT) {
            DepositIbcPacket memory depositPacket = abi.decode(data, (DepositIbcPacket));
            depositPackets[depositPacket.id].ibcStatus = IbcPacketStatus.TIMEOUT;
            balances[depositPacket.chainId] -= depositPacket.amount;
        } else if (packetType == IbcPacketType.BRIDGE) {
            BridgeIbcPacket memory bridgePacket = abi.decode(data, (BridgeIbcPacket));
            bridgePackets[bridgePacket.id].ibcStatus = IbcPacketStatus.TIMEOUT;
            balances[bridgePacket.toChainId] += bridgePacket.amount;
        } else {
            revert("Invalid packet type");
        }
    }
}
