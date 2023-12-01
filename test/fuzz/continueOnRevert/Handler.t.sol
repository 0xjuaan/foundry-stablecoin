// SPDX-License-Identifier: MIT
// PURPOSE: Narrow down the way we handle functions
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";

import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";

import {DecentralisedStableCoin} from "../../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";

contract Handler is Test {

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    // Only call redeemCollateral when we have collateral
    DSCEngine engine;
    DecentralisedStableCoin DSC;
    
    address weth;
    address wbtc;

    MockV3Aggregator wethPriceFeed;
    address[] collateralDepositers;

    constructor(DSCEngine _DSCEngine, DecentralisedStableCoin _DSC) {
        engine = _DSCEngine;
        DSC = _DSC;
        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = collateralTokens[0];
        wbtc = collateralTokens[1];

        wethPriceFeed = MockV3Aggregator(engine.getPriceFeed(weth));
    }






    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        address tokenAddress = _getCollateralTokenAddress(collateralSeed);


        vm.startPrank(msg.sender);
        ERC20Mock(tokenAddress).mint(msg.sender, amount);
        ERC20Mock(tokenAddress).approve(address(engine), amount);
        engine.depositCollateral(tokenAddress, amount);
        vm.stopPrank();

        collateralDepositers.push(msg.sender);
      
    }

    function redeemCollateral(uint256 collateralSeed, uint256 redeemAmount) public {

        address tokenAddress = _getCollateralTokenAddress(collateralSeed);

        uint256 maxRedeemAmount = engine.getAmountCollateralDeposited(tokenAddress, msg.sender);
        
        if (maxRedeemAmount <= 1) {
            return;
        }
        
        redeemAmount = bound(redeemAmount, 1, maxRedeemAmount);

        
        engine.redeemCollateral(tokenAddress, redeemAmount);
      
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {

        if (collateralDepositers.length == 0) {
            return;
        }
        address sender = collateralDepositers[addressSeed % collateralDepositers.length];

        uint256 collateralValue = engine.getTotalCollateralValue(sender);

        if (collateralValue <= 1) {
            return;
        }
        (uint256 totalDSCMinted, ) = engine._getAccountInformation(sender);

        int256 amountToMint = int256(collateralValue/2) - int256(totalDSCMinted);
        if (amountToMint <= 0) {
            return;
        }
        amount = bound(amount, 1, collateralValue/2 - totalDSCMinted);

        vm.prank(sender);
        engine.mintDSC(amount);
    }

    // Breaks our invariant
    /*function updateCollateralPrice(uint256 collateralSeed, uint96 price) public {
        int256 newPrice = int256(uint256(price));
        newPrice = bound(newPrice, 1e18, 3e18);
        wethPriceFeed.updateAnswer(newPrice);
    }*/


    // Helper functions
    function _getCollateralTokenAddress(uint256 collateralSeed) private view returns (address) {

        if (collateralSeed % 2 == 0) {
            return weth;
        } 
        return wbtc;
    }
}