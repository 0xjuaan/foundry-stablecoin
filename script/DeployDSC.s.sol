// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {DecentralisedStableCoin} from "../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralisedStableCoin, DSCEngine, HelperConfig) {

        HelperConfig config = new HelperConfig();

        (address wethUSDPriceFeed, address wbtcUSDPriceFeed, address weth, address wbtc, uint256 deployerKey) = config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUSDPriceFeed, wbtcUSDPriceFeed];


        vm.startBroadcast(deployerKey);
        DecentralisedStableCoin DSC = new DecentralisedStableCoin();
        console.log(DSC.owner());
        console.log(address(DSC));
        
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(DSC)); // takes in tokenAddresses[], priceFeeds[], dscAddress[]
        DSC.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (DSC, engine, config);
    }
}