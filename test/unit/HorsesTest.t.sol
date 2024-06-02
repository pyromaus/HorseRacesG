//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployHorses} from "../../script/DeployHorses.s.sol";
import {HorseRaces} from "../../src/HorseRaces.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract HorsesTest is Test {
    // events
    event EnteredRace(address indexed player);
    event WinnerPicked(uint indexed pony);

    HorseRaces wranglerUnit;
    HelperConfig helperConfig;
    address public PLAYER = makeAddr("player");
    address public BROKEE = makeAddr("brokee");
    uint public constant STARTINGUSERBALANCE = 10 ether;

    uint enterFee;
    uint interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address linkToken;
    uint horse1;
    uint horse2;
    uint horse3;
    uint horse4;

    function setUp() external {
        DeployHorses deployer = new DeployHorses();
        (wranglerUnit, helperConfig) = deployer.run();
        (
            enterFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            linkToken,

        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTINGUSERBALANCE);
        horse1 = wranglerUnit.newHorse("flea biscuit", 80);
        horse2 = wranglerUnit.newHorse("bobby", 50);
        horse3 = wranglerUnit.newHorse("beats by dre", 30);
        horse4 = wranglerUnit.newHorse("whistler", 69);
    }

    function testRaceStartsGood() public view {
        assert(wranglerUnit.getRaceStatus() == HorseRaces.RaceStatus.OPEN);
    }

    function testHorseCreationWorks() public view {
        assert(wranglerUnit.getHorseInfo(horse2).winOdds == 50);
        assert(wranglerUnit.getHorseInfo(horse3).horseId == horse3);
        assert(wranglerUnit.SEQ_horseID() == 4);
    }

    // placeBet
    function testBettingInsufficientFundsRevert() public {
        vm.prank(BROKEE);
        vm.expectRevert(HorseRaces.HorseRaces__NotEnoughETH.selector);
        // thats how you select errors
        wranglerUnit.placeBet(horse2);
    }

    function testBettingRecordsTheBets() public {
        vm.prank(PLAYER);
        wranglerUnit.placeBet{value: enterFee}(horse3);
        address better = wranglerUnit.getBetters(horse3)[0];
        assert(better == PLAYER);
    }

    function testBettingRecordsPlayer() public {
        vm.prank(PLAYER);
        wranglerUnit.placeBet{value: enterFee}(horse3);
        address playerRecorded = wranglerUnit.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnterEmitsEvent() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(wranglerUnit));
        vm.recordLogs();
        emit EnteredRace(PLAYER);
        wranglerUnit.placeBet{value: enterFee}(horse3); // this transaction emits the previous line's event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = (entries[1].topics[1]);
        emit log_bytes32(requestId);
    }

    function testRaceClosedWhileCalc() public raceEnteredAndTimePassed {
        wranglerUnit.performUpkeep("");

        vm.expectRevert(HorseRaces.HorseRaces__NotOpen.selector);
        vm.prank(PLAYER);
        wranglerUnit.placeBet{value: enterFee}(horse2);
    }

    function testCheckUpkeepReturnsFalseIfTooPoor() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = wranglerUnit.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaceClosed()
        public
        raceEnteredAndTimePassed
    {
        wranglerUnit.performUpkeep("");

        (bool upkeepNeeded, ) = wranglerUnit.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfTimeNotPassed() public {
        vm.prank(PLAYER);
        wranglerUnit.placeBet{value: enterFee}(horse1);
        vm.warp(block.timestamp + interval - 30);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = wranglerUnit.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenAllGood()
        public
        raceEnteredAndTimePassed
    {
        (bool upkeepNeeded, ) = wranglerUnit.checkUpkeep("");
        assert(upkeepNeeded);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepTrue()
        public
        raceEnteredAndTimePassed
    {
        wranglerUnit.performUpkeep(""); // act + assert
    }

    function testPerformUpkeepRevertsIfCheckUpkeepFalse() public {
        uint currentBal = 0;
        uint numPlayaz = 0;
        HorseRaces.RaceStatus rStatus = wranglerUnit.getRaceStatus();
        vm.expectRevert(
            abi.encodeWithSelector(
                HorseRaces.HorseRaces__UpkeepNotNeeded.selector,
                currentBal,
                numPlayaz,
                rStatus
            )
        );
        // vm.expectRevert();
        wranglerUnit.performUpkeep("");
    }

    function testSameAsAboveWrittenDifferently() public {
        uint balance = 0;
        uint playerCount = 0;
        uint raceStatus = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                HorseRaces.HorseRaces__UpkeepNotNeeded.selector,
                balance,
                playerCount,
                raceStatus
            )
        );

        wranglerUnit.performUpkeep("");
    }

    modifier raceEnteredAndTimePassed() {
        vm.prank(PLAYER);
        wranglerUnit.placeBet{value: enterFee}(horse1);
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaceStatusAndEmitsRequestId()
        public
        raceEnteredAndTimePassed
    {
        vm.recordLogs();
        wranglerUnit.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        HorseRaces.RaceStatus rStatus = wranglerUnit.getRaceStatus();

        assert(uint(requestId) > 0);
        assert(uint(rStatus) == 1);
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint randomRequestId
    ) public raceEnteredAndTimePassed skipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(wranglerUnit)
        );
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raceEnteredAndTimePassed
        skipFork
    {
        uint additionalEntrants = 3;
        uint startingIndex = 1; // some more horses

        console.log("1st addy balance before payout: ", PLAYER.balance);

        for (
            uint i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARTINGUSERBALANCE);
            wranglerUnit.placeBet{value: enterFee}(i); // they all enter
        }

        uint balanceB4Payout = wranglerUnit.getBettingPool();
        uint balance2 = address(this).balance;

        vm.recordLogs();
        wranglerUnit.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; // get the request ID for the VRF

        uint previousTimestamp = wranglerUnit.getLastTimestamp();

        vm.expectEmit(false, false, false, false, address(wranglerUnit));
        emit WinnerPicked(3);
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint(requestId),
            address(wranglerUnit)
        );

        uint winningHorse = wranglerUnit.getWinningHorseID();
        uint betterCount = wranglerUnit.getBetters(winningHorse).length;

        for (uint i = 0; i < wranglerUnit.getHorseCount(); i++) {
            address[] memory betters = wranglerUnit.getBetters(i + 1);
            console.log("Betters for Horse #", i + 1);
            for (uint x = 0; x < betters.length; x++) {
                console.log(betters[x]);
            }
        }
        console.log("Balance of address(this) lol: ", balance2);
        console.log("Winning Horse ID: ", winningHorse);
        console.log("This horse had this many bets: ", betterCount);
        console.log("Players length: ", wranglerUnit.getPlayersLength());
        console.log("Winning Bettors: ");
        for (uint i = 0; i < wranglerUnit.getRecentWinners().length; i++) {
            console.log(wranglerUnit.getRecentWinners()[i]);
        }
        console.log(wranglerUnit.getWinningHorseID());

        uint payout = balanceB4Payout / betterCount;

        assert(uint(wranglerUnit.getRaceStatus()) == 0);
        //assert(wranglerUnit.getRecentWinner() != address(0));
        //assert(wranglerUnit.getPlayersLength() == 0);
        assert(previousTimestamp < wranglerUnit.getLastTimestamp());
        console.log(
            "Balance of 1st winner: ",
            wranglerUnit.getRecentWinners()[0].balance
        );
        console.log(
            "Balance of 2nd: ",
            wranglerUnit.getRecentWinners()[1].balance
        );
        console.log("Balance of contract: ", address(wranglerUnit).balance);
        for (uint i = 0; i < wranglerUnit.getRecentWinners().length; i++) {
            assert(
                wranglerUnit.getRecentWinners()[i].balance ==
                    STARTINGUSERBALANCE + payout - enterFee
            );
        }

        wranglerUnit.resetRace();
        //assert(wranglerUnit.getBetters(1)[0] == address(0));
        //assert(wranglerUnit.getRecentWinners()[0] == address(0));
        assert(wranglerUnit.getPlayersLength() == 0);
    }
}
