// SPDX-License-Identifier: MIT
// PURPOSE: Narrow down the way we handle functions
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract Handler is Test {

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    // Only call redeemCollateral when we have collateral
    DSCEngine engine;
    DecentralisedStableCoin DSC;
    
    address weth;
    address wbtc;

    constructor(DSCEngine _DSCEngine, DecentralisedStableCoin _DSC) {
        engine = _DSCEngine;
        DSC = _DSC;
        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = collateralTokens[0];
        wbtc = collateralTokens[1];
    }






    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        address tokenAddress = _getCollateralTokenAddress(collateralSeed);


                
        vm.startPrank(msg.sender);
        ERC20Mock(tokenAddress).mint(msg.sender, amount);
        ERC20Mock(tokenAddress).approve(address(engine), amount);
        engine.depositCollateral(tokenAddress, amount);
        vm.stopPrank();

    }


    // Helper functions
    function _getCollateralTokenAddress(uint256 collateralSeed) private view returns (address) {

        if (collateralSeed % 2 == 0) {
            return weth;
        } 
        return wbtc;
    }
}