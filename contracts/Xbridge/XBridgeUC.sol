//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "../base/UniversalChanIbcApp.sol";

contract XBridgeUC is UniversalChanIbcApp {
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

    event Deposit(bytes32 indexed id, uint256 indexed chainId, address sender, uint256 amount);
    event Bridge(bytes32 indexed id, uint256 indexed fromChainId, uint256 indexed toChainId, address sender, uint256 amount);
    event RecvDeposit(bytes32 indexed id, uint256 indexed chainId, address sender, uint256 amount);
    event RecvBridge(bytes32 indexed id, uint256 indexed fromChainId, uint256 indexed toChainId, address sender, uint256 amount);
    event AckDeposit(bytes32 indexed id, uint256 indexed chainId, address sender, uint256 amount);
    event AckBridge(bytes32 indexed id, uint256 indexed fromChainId, uint256 indexed toChainId, address sender, uint256 amount);

    constructor(address _middleware) UniversalChanIbcApp(_middleware) {}

    function setChainId(uint256 _chainId) external onlyOwner {
        chainId = _chainId;
    }

    function deposit(
        address destPortAddr,
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
        bytes memory payload = abi.encode(IbcPacketType.DEPOSIT, abi.encode(ibcPacket));
        uint64 timeoutTimestamp = uint64((block.timestamp + timeoutSeconds) * 1000000000);

        IbcUniversalPacketSender(mw).sendUniversalPacket(
            channelId, IbcUtils.toBytes32(destPortAddr), payload, timeoutTimestamp
        );
        emit Deposit(id, chainId, msg.sender, amount);
    }

    function bridge(
        address destPortAddr,
        bytes32 channelId,
        uint64 timeoutSeconds,
        uint256 toChainId
    ) external payable {
        require(balances[toChainId] >= msg.value, "Insufficient balance");
        uint256 amount = msg.value;
        balances[chainId] += amount;
        balances[toChainId] -= amount;
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
        bytes memory payload = abi.encode(IbcPacketType.BRIDGE, abi.encode(ibcPacket));
        uint64 timeoutTimestamp = uint64((block.timestamp + timeoutSeconds) * 1000000000);

        IbcUniversalPacketSender(mw).sendUniversalPacket(
            channelId, IbcUtils.toBytes32(destPortAddr), payload, timeoutTimestamp
        );
        emit Bridge(id, chainId, toChainId, msg.sender, amount);
    }

    // IBC logic

    /**
     * @dev Packet lifecycle callback that implements packet receipt logic and returns and acknowledgement packet.
     *      MUST be overriden by the inheriting contract.
     *
     * @param channelId the ID of the channel (locally) the packet was received on.
     * @param packet the Universal packet encoded by the source and relayed by the relayer.
     */
    function onRecvUniversalPacket(bytes32 channelId, UniversalPacket calldata packet)
        external
        override
        onlyIbcMw
        returns (AckPacket memory ackPacket)
    {
        recvedPackets.push(UcPacketWithChannel(channelId, packet));

        (IbcPacketType packetType, bytes memory data) = abi.decode(
            packet.appData,
            (IbcPacketType, bytes)
        );

        if (packetType == IbcPacketType.DEPOSIT) {
            DepositIbcPacket memory depositPacket = abi.decode(data, (DepositIbcPacket));
            balances[depositPacket.chainId] += depositPacket.amount;
            emit RecvDeposit(depositPacket.id, depositPacket.chainId, depositPacket.sender, depositPacket.amount);
        } else if (packetType == IbcPacketType.BRIDGE) {
            BridgeIbcPacket memory bridgePacket = abi.decode(data, (BridgeIbcPacket));
            balances[bridgePacket.fromChainId] += bridgePacket.amount;
            balances[bridgePacket.toChainId] -= bridgePacket.amount;
            payable(bridgePacket.sender).transfer(bridgePacket.amount);
            emit RecvBridge(bridgePacket.id, bridgePacket.fromChainId, bridgePacket.toChainId, bridgePacket.sender, bridgePacket.amount);
        } else{
            revert("Invalid packet type");
        }

        return AckPacket(true, packet.appData);
    }

    /**
     * @dev Packet lifecycle callback that implements packet acknowledgment logic.
     *      MUST be overriden by the inheriting contract.
     *
     * @param channelId the ID of the channel (locally) the ack was received on.
     * @param packet the Universal packet encoded by the source and relayed by the relayer.
     * @param ack the acknowledgment packet encoded by the destination and relayed by the relayer.
     */
    function onUniversalAcknowledgement(bytes32 channelId, UniversalPacket memory packet, AckPacket calldata ack)
        external
        override
        onlyIbcMw
    {
        ackPackets.push(UcAckWithChannel(channelId, packet, ack));

        (IbcPacketType packetType, bytes memory data) = abi.decode(
            ack.data,
            (IbcPacketType, bytes)
        );
        if (packetType == IbcPacketType.DEPOSIT) {
            DepositIbcPacket memory depositPacket = abi.decode(data, (DepositIbcPacket));
            depositPackets[depositPacket.id].ibcStatus = IbcPacketStatus.ACKED;
            emit AckDeposit(depositPacket.id, depositPacket.chainId, depositPacket.sender, depositPacket.amount);
        } else if (packetType == IbcPacketType.BRIDGE) {
            BridgeIbcPacket memory bridgePacket = abi.decode(data, (BridgeIbcPacket));
            bridgePackets[bridgePacket.id].ibcStatus = IbcPacketStatus.ACKED;
            emit AckBridge(bridgePacket.id, bridgePacket.fromChainId, bridgePacket.toChainId, bridgePacket.sender, bridgePacket.amount);
        } else {
            revert("Invalid packet type");
        }
    }

    /**
     * @dev Packet lifecycle callback that implements packet receipt logic and return and acknowledgement packet.
     *      MUST be overriden by the inheriting contract.
     *      NOT SUPPORTED YET
     *
     * @param channelId the ID of the channel (locally) the timeout was submitted on.
     * @param packet the Universal packet encoded by the counterparty and relayed by the relayer
     */
    function onTimeoutUniversalPacket(bytes32 channelId, UniversalPacket calldata packet) external override onlyIbcMw {
        timeoutPackets.push(UcPacketWithChannel(channelId, packet));
        // do logic
    }
}
