// total supply of DSC < total value of collateral
// getter/view functions should never revert (evergreen invariant- for every fn )

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {

    DeployDSC deployer;
    DSCEngine engine;
    DecentralisedStableCoin DSC;
    HelperConfig config;

    address weth;
    address wbtc;

    address wethPriceFeed;
    address wbtcPriceFeed;

    function setUp() public {
        // Make new deploy script contract instance (to deploy the stablecoin)
        deployer = new DeployDSC();

        // deploy DSC with engine
        (DSC, engine, config ) = deployer.run();
        (wethPriceFeed,wbtcPriceFeed,weth,wbtc, ) = config.activeNetworkConfig();

        Handler handler = new Handler(engine, DSC);
        targetContract(address(handler));
    }

    function invariant_totalSupplyLessThanTotalCollateral() public view {
        uint256 totalSupply = DSC.totalSupply();
        uint256 totalWETH = ERC20Mock(weth).balanceOf(address(engine));
        uint256 totalWBTC = ERC20Mock(wbtc).balanceOf(address(engine));

        uint256 totalCollateralValue = engine.getUSDPrice(weth)*totalWETH + engine.getUSDPrice(wbtc)*totalWBTC;
        assert(totalSupply < totalCollateralValue);
    }
}