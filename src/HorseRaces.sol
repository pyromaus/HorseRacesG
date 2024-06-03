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

    enum RaceStatus {
        OPEN,
        CALCULATING
    }

    struct Horse {
        uint horseId;
        string name;
        uint8 winOdds;
    }

    // win odds are not yet implemented in the calculation of the winner

    mapping(uint horseId => Horse horse) private s_theStable; // the current supply of race horses to bet on
    mapping(uint horseId => address[] betters) private s_betters;
    mapping(uint horseId => uint activeBets) private s_activeBetCount;

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint public SEQ_horseID = 0; // horse id starting at 0, becomes 1 when first horse is conjured

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
    uint private s_bettingPool;

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

    /* conjures a horse to participate in the races, with a horse ID, name, and win odds */

    function placeBet(uint _pony) public payable {
        if (msg.value < i_enterFee) {
            revert HorseRaces__NotEnoughETH();
        }
        if (s_raceStatus != RaceStatus.OPEN) {
            revert HorseRaces__NotOpen();
        }
        s_betters[_pony].push(msg.sender);
        s_players.push(payable(msg.sender));
        s_activeBetCount[SEQ_horseID] = s_activeBetCount[SEQ_horseID] + 1;
        uint enterFeeLessOurCut = (msg.value * 19) / 20;
        s_bettingPool += enterFeeLessOurCut;

        emit EnteredRace(msg.sender);
    }

    /* called by the user to place a bet on a horse, takes horse ID as input
    they must send at least the enter fee
    s_betters : mapping of each horse's bettors
    horse race contract keeps 5% of entrance fees */

    function startRace() public /*uint8 _horseCount*/ {
        
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

    /* called by user or can be called at a predefined interval
    requests a random number, race is not open at this time */

    function fulfillRandomWords(
        uint /*requestId*/,
        uint[] memory randomWords
    ) internal override {
        
        uint indexOfWinner = randomWords[0] % SEQ_horseID;
       
        emit WinnerPicked(indexOfWinner);
        finalizeRace(indexOfWinner);
    }

    /* called by chainlink node
    index of winning horse is calculated */

    function finalizeRace(uint _indexOfWinner) internal {

        s_recentWinningHorse = s_theStable[_indexOfWinner].horseId;
        uint winningPortion = s_bettingPool / s_betters[_indexOfWinner].length;
        for (uint i = 0; i < s_betters[_indexOfWinner].length; i++) {
            address payee = s_betters[_indexOfWinner][i];
            s_recentWinners.push(payable(payee));
        }

        s_latestTimestamp = block.timestamp;
        for (uint i = 0; i < s_betters[_indexOfWinner].length; i++) {
            (bool success, ) = s_betters[_indexOfWinner][i].call{
                value: winningPortion
            }("");
            if (!success) {
                revert HorseRaces__TransferFailed();
            }
        }
        s_raceStatus = RaceStatus.OPEN;
    }

    /* payouts are calculated and sent, recent winners are updated
    payout = entire contract balance minus 5%, divided by number of bets on the horse */

    function resetRace() public {
        for (uint i = 0; i < SEQ_horseID; i++) {
            s_betters[i + 1] = new address[](0);
        }
        s_recentWinners = new address payable[](0);
        s_players = new address payable[](0);
    }

    /* resets the bets list */

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

    function getHorseCount() external view returns (uint) {
        return SEQ_horseID;
    }

    function getActiveBetCount(uint _pony) external view returns (uint) {
        return s_activeBetCount[_pony];
    }

    function getBettingPool() external view returns (uint) {
        return s_bettingPool;
    }

    function getRecentWinners()
        external
        view
        returns (address payable[] memory)
    {
        return s_recentWinners;
    }

    function getPlayersLength() external view returns (uint) {
        return s_players.length;
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
