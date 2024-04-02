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
        WITHDRAW,
        BRIDGE
    }

    struct DepositIbcPacket {
        bytes32 id;
        uint256 chainId;
        address sender;
        uint256 amount;
        IbcPacketStatus ibcStatus;
    }

    struct WithdrawIbcPacket {
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
    mapping(bytes32 => WithdrawIbcPacket) public withdrawPackets;
    mapping(bytes32 => BridgeIbcPacket) public bridgePackets;
    mapping(uint256 => uint256) public balances;

    event Deposit(bytes32 indexed id, uint256 indexed chainId, address sender, uint256 amount);
    event Withdrawal(bytes32 indexed id, uint256 indexed chainId, address sender, uint256 amount);
    event Bridge(bytes32 indexed id, uint256 indexed fromChainId, uint256 indexed toChainId, address sender, uint256 amount);
    event RecvDeposit(bytes32 indexed id, uint256 indexed chainId, address sender, uint256 amount);
    event RecvWithdrawal(bytes32 indexed id, uint256 indexed chainId, address sender, uint256 amount);
    event RecvBridge(bytes32 indexed id, uint256 indexed fromChainId, uint256 indexed toChainId, address sender, uint256 amount);
    event AckDeposit(bytes32 indexed id, uint256 indexed chainId, address sender, uint256 amount);
    event AckWithdrawal(bytes32 indexed id, uint256 indexed chainId, address sender, uint256 amount);
    event AckBridge(bytes32 indexed id, uint256 indexed fromChainId, uint256 indexed toChainId, address sender, uint256 amount);

    constructor(IbcDispatcher _dispatcher) CustomChanIbcApp(_dispatcher) {}

    function setChainId(uint256 _chainId) external onlyOwner {
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
        emit Deposit(id, chainId, msg.sender, amount);
    }

    function withdraw(
        bytes32 channelId,
        uint64 timeoutSeconds,
        uint256 amount
    ) external onlyOwner {
        require(balances[chainId] >= amount, "Insufficient balance");
        balances[chainId] -= amount;
        bytes32 id = keccak256(abi.encodePacked(msg.sender, amount, block.timestamp));
        WithdrawIbcPacket memory ibcPacket = WithdrawIbcPacket({
            id: id,
            chainId: chainId,
            sender: msg.sender,
            amount: amount,
            ibcStatus: IbcPacketStatus.UNSENT
        });
        withdrawPackets[id] = ibcPacket;
        bytes memory data = abi.encode(IbcPacketType.WITHDRAW, abi.encode(ibcPacket));
        sendPacket(channelId, timeoutSeconds, data);
        emit Withdrawal(id, chainId, msg.sender, amount);
    }

    function bridge(
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
        bytes memory data = abi.encode(IbcPacketType.BRIDGE, abi.encode(ibcPacket));
        sendPacket(channelId, timeoutSeconds, data);
        emit Bridge(id, chainId, toChainId, msg.sender, amount);
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
            emit RecvDeposit(depositPacket.id, depositPacket.chainId, depositPacket.sender, depositPacket.amount);
        } else if (packetType == IbcPacketType.WITHDRAW) {
            WithdrawIbcPacket memory withdrawPacket = abi.decode(data, (WithdrawIbcPacket));
            balances[withdrawPacket.chainId] -= withdrawPacket.amount;
            emit RecvWithdrawal(withdrawPacket.id, withdrawPacket.chainId, withdrawPacket.sender, withdrawPacket.amount);
        } else if (packetType == IbcPacketType.BRIDGE) {
            BridgeIbcPacket memory bridgePacket = abi.decode(data, (BridgeIbcPacket));
            balances[bridgePacket.fromChainId] += bridgePacket.amount;
            balances[bridgePacket.toChainId] -= bridgePacket.amount;
            payable(bridgePacket.sender).transfer(bridgePacket.amount);
            emit RecvBridge(bridgePacket.id, bridgePacket.fromChainId, bridgePacket.toChainId, bridgePacket.sender, bridgePacket.amount);
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
            emit AckDeposit(depositPacket.id, depositPacket.chainId, depositPacket.sender, depositPacket.amount);
        } else if (packetType == IbcPacketType.WITHDRAW) {
            WithdrawIbcPacket memory withdrawPacket = abi.decode(data, (WithdrawIbcPacket));
            withdrawPackets[withdrawPacket.id].ibcStatus = IbcPacketStatus.ACKED;
            payable(msg.sender).transfer(withdrawPacket.amount);
            emit AckWithdrawal(withdrawPacket.id, withdrawPacket.chainId, withdrawPacket.sender, withdrawPacket.amount);
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
        } else if (packetType == IbcPacketType.WITHDRAW) {
            WithdrawIbcPacket memory withdrawPacket = abi.decode(data, (WithdrawIbcPacket));
            withdrawPackets[withdrawPacket.id].ibcStatus = IbcPacketStatus.TIMEOUT;
            balances[withdrawPacket.chainId] += withdrawPacket.amount;
        } else if (packetType == IbcPacketType.BRIDGE) {
            BridgeIbcPacket memory bridgePacket = abi.decode(data, (BridgeIbcPacket));
            bridgePackets[bridgePacket.id].ibcStatus = IbcPacketStatus.TIMEOUT;
            balances[bridgePacket.fromChainId] -= bridgePacket.amount;
            balances[bridgePacket.toChainId] += bridgePacket.amount;
        } else {
            revert("Invalid packet type");
        }
    }
}
