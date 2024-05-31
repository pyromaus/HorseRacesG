// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HorseRaces} from "../src/HorseRaces.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , , , , uint deployerKey) = helperConfig
            .activeNetworkConfig();
        return createSubscription(vrfCoordinator, deployerKey);
    }

    function createSubscription(
        address _vrf,
        uint deployerKey
    ) public returns (uint64) {
        console.log("Creating sub on chain ID: ", block.chainid);
        vm.broadcast(deployerKey);
        uint64 subId = VRFCoordinatorV2Mock(_vrf).createSubscription();
        console.log("Returned Sub ID: ", subId);
        console.log("Update Sub ID in helperConfig");
        return subId;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUNDAMOUNT = 3 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfMock,
            ,
            uint64 subId,
            ,
            address link,
            uint deployerKey
        ) = helperConfig.activeNetworkConfig();
        fundSubscription(vrfMock, subId, link, deployerKey);
    }

    function fundSubscription(
        address vrf,
        uint64 subId,
        address link,
        uint deployerKey
    ) public {
        console.log("Sub:", subId);
        console.log("VRF:", vrf);
        console.log("Link", link);
        if (block.chainid == 31337) {
            vm.broadcast(deployerKey);
            VRFCoordinatorV2Mock(vrf).fundSubscription(subId, FUNDAMOUNT);
        } else {
            vm.broadcast(deployerKey);
            LinkToken(link).transferAndCall(vrf, FUNDAMOUNT, abi.encode(subId));
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumerUsingConfig(address consumer) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfMock,
            ,
            uint64 subId,
            ,
            ,
            uint deployerKey
        ) = helperConfig.activeNetworkConfig();
        addConsumer(consumer, vrfMock, subId, deployerKey);
    }

    function addConsumer(
        address consumer,
        address vrf,
        uint64 subId,
        uint deployerKey
    ) public {
        console.log("Sub:", subId);
        console.log("VRF:", vrf);
        console.log("Consumer", consumer);
        vm.broadcast(deployerKey);
        VRFCoordinatorV2Mock(vrf).addConsumer(subId, consumer);
    }

    function run() external {
        address wranglerRace = DevOpsTools.get_most_recent_deployment(
            "HorseRaces",
            block.chainid
        );
        addConsumerUsingConfig(wranglerRace);
    }
}

contract ConjureHorses is Script {
    function conjureGenericHorses(uint8 _howManyPony) public returns (uint8) {
        address wranglerUnit = DevOpsTools.get_most_recent_deployment(
            "HorseRaces",
            block.chainid
        );
        for (uint i = 0; i < _howManyPony; i++) {
            HorseRaces(wranglerUnit).newHorse("pony", 55);
        }
        return HorseRaces(wranglerUnit).getPlayersLength();
    }

    function conjureCustomHorses() public returns (uint8) {
        address wranglerUnit = DevOpsTools.get_most_recent_deployment(
            "HorseRaces",
            block.chainid
        );
        HorseRaces(wranglerUnit).newHorse("flea biscuit", 80);
        HorseRaces(wranglerUnit).newHorse("bobby", 50);
        HorseRaces(wranglerUnit).newHorse("bobby lee", 51);
        HorseRaces(wranglerUnit).newHorse("beats by dre", 30);
        HorseRaces(wranglerUnit).newHorse("whistler", 69);
        HorseRaces(wranglerUnit).newHorse("squamsquatch", 42);
        HorseRaces(wranglerUnit).newHorse("seattle kangz", 60);

        return HorseRaces(wranglerUnit).getPlayersLength();
    }

    function run() external returns (uint8) {
        // uint8 howManyHorsesYouNeedBrah = 10;
        // return conjureGenericHorses(howManyHorsesYouNeedBrah);
        return conjureCustomHorses();
    }
}
