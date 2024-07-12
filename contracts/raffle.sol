// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

error Raffle_NotEnoughAmount();
error Raffle_RaffleClosed();
error Raffle_NoUpkeepNeeded();

contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    enum Status {
        Open,
        Calculating
    }

    VRFCoordinatorV2Interface private immutable vrfCoordinator;
    uint256 private immutable minAmount;
    address payable[] private participants;
    uint256 private immutable interval;
    uint256 private lastTime;
    bytes32 private immutable gasLane;
    uint64 private immutable subscriptionId;
    uint32 private immutable gasLimit;
    uint16 private constant CONFIRMATIONS = 1;
    uint32 private constant NUM_WORDS = 1;
    Status private state;

    event Recent(address indexed entry);
    event WinnerPicked(address indexed winner);
    event random(uint256 randomnumber);

    constructor(
        address _vrfCoordinator,
        uint256 _minAmount,
        uint256 _interval,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _gasLimit
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        minAmount = _minAmount;
        state = Status.Open;
        interval = _interval;
        lastTime = block.timestamp;
        gasLane = _gasLane;
        subscriptionId = _subscriptionId;
        gasLimit = _gasLimit;
    }

    function enter() public payable {
        if (msg.value < minAmount) {
            revert Raffle_NotEnoughAmount();
        }
        if (state != Status.Open) {
            revert Raffle_RaffleClosed();
        }
        participants.push(payable(msg.sender));
        emit Recent(msg.sender);
    }

    function checkUpkeep(
        bytes calldata
    ) public view override returns (bool upkeepNeeded, bytes memory) {
        bool hasBalance = address(this).balance > 0;
        bool isOpen = state == Status.Open;
        bool hasParticipants = participants.length > 0;
        bool timePassed = (block.timestamp - lastTime) > interval;
        upkeepNeeded = hasBalance && isOpen && hasParticipants && timePassed;
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata) external override {
        bool hasBalance = address(this).balance > 0;
        bool isOpen = state == Status.Open;
        bool hasParticipants = participants.length > 0;
        bool timePassed = (block.timestamp - lastTime) > interval;
        bool upkeepNeeded = hasBalance &&
            isOpen &&
            hasParticipants &&
            timePassed;

        if (!upkeepNeeded) {
            revert Raffle_NoUpkeepNeeded();
        }

        state = Status.Calculating;
        uint256 requestid = vrfCoordinator.requestRandomWords(
            gasLane,
            subscriptionId,
            CONFIRMATIONS,
            gasLimit,
            NUM_WORDS
        );
        emit random(requestid);
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        uint256 index = randomWords[0] % participants.length;
        address payable winner = participants[index];
        participants = new address payable[](0); // Correctly initialize the participants array
        state = Status.Open;
        lastTime = block.timestamp;
        (bool success, ) = winner.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
        emit WinnerPicked(winner);
    }
}
