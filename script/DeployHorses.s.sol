// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HorseRaces} from "../src/HorseRaces.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DeployHorses is Script {
    function run() external returns (HorseRaces, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint enterFee,
            uint interval,
            address vrfCoordinator,
            bytes32 gasLane,
            uint64 subscriptionId,
            uint32 callbackGasLimit,
            address link,
            uint deployerKey
        ) = helperConfig.activeNetworkConfig();

        if (subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            subscriptionId = createSubscription.createSubscription(
                vrfCoordinator,
                deployerKey
            );

            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                vrfCoordinator,
                subscriptionId,
                link,
                deployerKey
            );
        }

        vm.broadcast();
        HorseRaces wrangleanSchool = new HorseRaces(
            enterFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit
        );

        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(wrangleanSchool),
            vrfCoordinator,
            subscriptionId,
            deployerKey
        );

        return (wrangleanSchool, helperConfig);
    }
}
