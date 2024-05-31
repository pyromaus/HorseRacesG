//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * @title Horse Races
 * @author Serg
 * @notice Smart contract with verifiably random horse racing
 * @dev Chainlink VRFv2, Chainlink Automation
 */

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract HorseRaces is VRFConsumerBaseV2 {
    /** errors */
    error HorseRaces__NotEnoughETH();
    error HorseRaces__TenHorseMinimum();
    error HorseRaces__TooEarly();
    error HorseRaces__TransferFailed();
    error HorseRaces__NotOpen();
    error HorseRaces__UpkeepNotNeeded(
        uint currentBalance,
        uint playerCount,
        uint raceStatus
    );

    /** type dec */
    enum RaceStatus {
        OPEN,
        CALCULATING
    }

    struct Horse {
        uint horseId;
        string name;
        uint8 winOdds;
    }

    mapping(uint horseId => Horse horse) private s_theStable;
    uint8[] private s_horseCount; // 22
    uint8 private s_activeHorseCount; // 7
    mapping(uint horseId => address[] betters) private s_betters;
    // mapping(address gambler => uint betHorseId) private s_activeBets;

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint public SEQ_horseID = 0;

    uint private immutable i_enterFee;
    uint private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint private s_latestTimestamp;
    address payable[] private s_recentWinners;
    uint private s_recentWinningHorse;
    RaceStatus private s_raceStatus;

    /** events */
    event EnteredRace(address indexed player);
    event WinnerPicked(uint indexed pony);
    event RequestedRaceRandomness(uint indexed requestId);

    constructor(
        uint _enterFee,
        uint _interval,
        address _vrfCoordinator,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        i_enterFee = _enterFee;
        i_interval = _interval;
        s_latestTimestamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        i_gasLane = _gasLane;
        i_subscriptionId = _subscriptionId;
        i_callbackGasLimit = _callbackGasLimit;
        s_raceStatus = RaceStatus.OPEN;
    }

    function newHorse(
        string memory _name,
        uint8 _winOdds
    ) public returns (uint) {
        SEQ_horseID++;
        s_theStable[SEQ_horseID] = Horse(SEQ_horseID, _name, _winOdds);
        return SEQ_horseID;
    }

    function placeBet(uint _pony) public payable {
        if (msg.value < i_enterFee) {
            revert HorseRaces__NotEnoughETH();
        }
        if (s_raceStatus != RaceStatus.OPEN) {
            revert HorseRaces__NotOpen();
        }
        s_betters[_pony].push(msg.sender);
        s_players.push(payable(msg.sender));
        emit EnteredRace(msg.sender);
    }

    function startRace() public /*uint8 _horseCount*/ {
        //s_activeHorseCount = _horseCount;
        uint requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaceRandomness(requestId);
    }

    function fulfillRandomWords(
        uint /*requestId*/,
        uint[] memory randomWords
    ) internal override {
        // checks, effects, interactions
        // checks/requires at the beginning. faster revert = less gas spent
        // effects (our own contract)
        // uint[] memory newRace;
        // for (uint i = 0; i < s_activeHorseCount; i++) {
        //     uint newContestantHorse = randomWords[i] % s_horseCount.length;
        //     newRace.push(newContestantHorse);
        // }
        uint indexOfWinner = randomWords[0] % SEQ_horseID;
        //s_recentWinningHorse = indexOfWinner;
        // address payable winner = s_players[indexOfWinner];
        //s_recentWinners = payable(s_betters[s_recentWinningHorse]);
        //s_raceStatus = RaceStatus.OPEN;
        //s_players = new address payable[](0);
        //s_latestTimestamp = block.timestamp;
        emit WinnerPicked(indexOfWinner);
        finalizeRace(indexOfWinner);
    }

    function finalizeRace(uint _indexOfWinner) internal {
        //uint randomNumber = 6;
        //uint winnerHorseId = s_theStable[randomNumber].horseId;
        s_recentWinners = new address payable[](0);
        s_recentWinningHorse = s_theStable[_indexOfWinner].horseId;
        uint winningPortion = address(this).balance /
            s_betters[_indexOfWinner].length;
        for (uint i = 0; i < s_betters[_indexOfWinner].length; i++) {
            address payee = s_betters[_indexOfWinner][i];
            s_recentWinners.push(payable(payee));
        }
        s_players = new address payable[](0);
        s_latestTimestamp = block.timestamp;
        for (uint i = 0; i < s_betters[_indexOfWinner].length; i++) {
            (bool success, ) = s_betters[_indexOfWinner][i].call{
                value: winningPortion
            }("");
            if (!success) {
                revert HorseRaces__TransferFailed();
            }
        }
        s_betters[_indexOfWinner] = new address payable[](0);
    }

    /** getters */

    function getEnterFee() external view returns (uint) {
        return i_enterFee;
    }

    function getRaceStatus() external view returns (RaceStatus) {
        return s_raceStatus;
    }

    function getPlayer(uint playerIndex) external view returns (address) {
        return s_players[playerIndex];
    }

    function getHorseInfo(uint _ponyId) external view returns (Horse memory) {
        return s_theStable[_ponyId];
    }

    function getBetters(uint _ponyId) external view returns (address[] memory) {
        return s_betters[_ponyId];
    }

    function getWinningHorseID() external view returns (uint) {
        return s_recentWinningHorse;
    }

    function getRecentWinners()
        external
        view
        returns (address payable[] memory)
    {
        return s_recentWinners;
    }

    function getPlayersLength() external view returns (uint8) {
        return uint8(s_players.length);
    }

    function getLastTimestamp() external view returns (uint) {
        return s_latestTimestamp;
    }

    function checkUpkeep(
        bytes memory /*checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool enoughTimeGoneBy = (block.timestamp - s_latestTimestamp) >=
            i_interval;
        bool isOpen = RaceStatus.OPEN == s_raceStatus;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (enoughTimeGoneBy && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert HorseRaces__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint(s_raceStatus)
            );
        }
        s_raceStatus = RaceStatus.CALCULATING;
        uint requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaceRandomness(requestId);
    }
}