// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
     
    DeployDSC deployer;
    HelperConfig config;
    DSCEngine engine;
    DecentralisedStableCoin DSC;

    address wethPriceFeed;
    address weth;
    
    function setUp() public {
        // Make new deploy script contract instance
        deployer = new DeployDSC();

        // deploy DSC with engine
        (DSC, engine, config ) = deployer.run();
        (wethPriceFeed,,weth,, ) = config.activeNetworkConfig();
    }

    // Test the pricefeed
    function testGetUSDPrice() public {
        uint256 usdValue = engine.getUSDPrice(wethPriceFeed);
        int256 expected = 2000e18;
        assertEq(usdValue, uint256(expected));
        
    }
}
