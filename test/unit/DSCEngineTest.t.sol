// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

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

    address wbtcPriceFeed;
    address wbtc;

    uint256 PRECISION = 1e18;

    address USER;
    address USER2;

    uint256 INITIAL_BALANCE = 10e18;

    ERC20Mock wethMock = ERC20Mock(weth);
    
    function setUp() public {
        // Make new deploy script contract instance (to deploy the stablecoin)
        deployer = new DeployDSC();

        // deploy DSC with engine
        (DSC, engine, config ) = deployer.run();
        (wethPriceFeed,wbtcPriceFeed,weth,wbtc, ) = config.activeNetworkConfig();
    }

    //Modifiers
    modifier basicUser() {
        USER = makeAddr("user1");
        deal(weth, USER, INITIAL_BALANCE);
        _;
    }

    modifier multiUser() {
        USER = makeAddr("user1");
        USER2 = makeAddr("user2");
        deal(weth, USER, INITIAL_BALANCE);
        deal(weth, USER2, INITIAL_BALANCE);
        _;
    }



    ///////////////////
    //Pricefeed Tests//
    ///////////////////

    // Test the pricefeed's ETH/USD value (hardcoded to use our mock pricefeed's predefined output value)
    function testGetUSDPrice() public {
        uint256 usdValue = engine.getUSDPrice(wethPriceFeed);
        int256 expected = 2000e18;
        assertEq(usdValue, uint256(expected));
    }


    //////////////
    //defi tests//
    //////////////

    function testMintDSCFailsWithoutCollateral() basicUser public {
        
        vm.prank(USER);

        uint256 expectedHealthFactor = 0;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, expectedHealthFactor));
        engine.mintDSC(5e18);
    }

    function testMintDSCPassesWithCollateral() basicUser public {
        
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), 3e18); // approve 3 weth to engine (3e18)
        engine.depositCollateral(weth, 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed));

        engine.mintDSC(1e18); // This should work for any amount that is less than or equal to 1.5e18 (Since the liquidation threshold is 50%)
        vm.stopPrank();
    }

    function testMintDSCFailsWithBadInput() basicUser public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDSC(0);
    }

    function testDepositFailsOnBadToken() basicUser public {
        vm.prank(USER);
        vm.expectRevert();
        engine.depositCollateral(makeAddr("SHIB"), 1e18);
    }

    function testDepositWorks() basicUser public {

        vm.startPrank(USER);
        uint256 DEPOSIT_AMOUNT_USD = 1e18;
        ERC20Mock(weth).approve(address(engine), 3e18);

        uint256 DEPOSIT_AMOUNT_ETH = DEPOSIT_AMOUNT_USD * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        engine.depositCollateral(weth, DEPOSIT_AMOUNT_ETH);

        assertEq(engine.getAmountCollateralDeposited(weth, USER), DEPOSIT_AMOUNT_ETH);

        assertEq(ERC20Mock(weth).balanceOf(USER), INITIAL_BALANCE - DEPOSIT_AMOUNT_ETH);
        vm.stopPrank();
    }

    function testBurnDSCFailsWhenNone() basicUser public {
        vm.prank(USER);
        vm.expectRevert();
        engine.burnDSC(1e18);
    }

    function testBurnDSCWorks() basicUser public {

        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        
        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited); // approve 3 weth to engine (3e18)
        engine.depositCollateral(weth, amountCollateralDeposited);

        engine.mintDSC(1e18); // This should work for any amount that is less than 1.5e18 (Since the liquidation threshold is 50%)
        DSC.approve(address(engine), 1e18);
        engine.burnDSC(DSC.balanceOf(USER));

        vm.stopPrank();
    }

    function testRedeemCollateralFailsBadHealth() basicUser public {

        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        
        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited);
        engine.depositCollateral(weth, amountCollateralDeposited);

        engine.mintDSC(1.5e18); // This is the max that we can mint, given the collateral value

        // Expect revert with health factor of 0.5 (it halved)
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, 0.5e18));
        engine.redeemCollateral(weth, amountCollateralDeposited / 2);

        vm.stopPrank();

    }

    function testRedeemCollateralWorks() basicUser public {
        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        
        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited);
        engine.depositCollateral(weth, amountCollateralDeposited);

        engine.mintDSC(1e18); // This is the max that we can mint, given the collateral value

        engine.redeemCollateral(weth, amountCollateralDeposited* PRECISION / 3e18);
        assertEq(engine.getHealthFactor(USER), 1e18);

        vm.stopPrank();
    }

    function testdepositCollateralAndMint() basicUser public {
        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        uint256 amountDSCToMint = 1e18;

        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited);
        engine.depositCollateralAndMint(weth, amountCollateralDeposited, amountDSCToMint);

        assertEq(engine.getAmountCollateralDeposited(weth, USER), amountCollateralDeposited);
        assertEq(DSC.balanceOf(USER), amountDSCToMint);
    }

    function testRedeemCollateralForDSCFailsWhenNotApprovedDSC() basicUser public {
        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        uint256 amountDSCToMint = 1.5e18;
        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited);
        engine.depositCollateralAndMint(weth, amountCollateralDeposited, amountDSCToMint);

        uint256 amountDSCToBurn = 7.5e17;
        uint256 amountCollateralToRedeem = amountCollateralDeposited / 2;

        
        vm.expectRevert();
        engine.redeemCollateralForDSC(weth, amountCollateralToRedeem, amountDSCToBurn);
        vm.stopPrank();
    }

    function testRedeemCollateralForDSCFailsWhenRedeemingMuch() basicUser public {
        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        uint256 amountDSCToMint = 1.5e18;
        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited);
        engine.depositCollateralAndMint(weth, amountCollateralDeposited, amountDSCToMint);

        uint256 amountDSCToBurn = 7.5e17;
        uint256 amountCollateralToRedeem = amountCollateralDeposited;

        DSC.approve(address(engine), amountDSCToBurn);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, 0));
        engine.redeemCollateralForDSC(weth, amountCollateralToRedeem, amountDSCToBurn);

        vm.stopPrank();
    }

    function testRedeemCollateralForDSCWorks() basicUser public {
        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        uint256 amountDSCToMint = 1.5e18;
        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited);
        engine.depositCollateralAndMint(weth, amountCollateralDeposited, amountDSCToMint);

        uint256 amountDSCToBurn = 7.5e17;
        uint256 amountCollateralToRedeem = amountCollateralDeposited / 2;

        DSC.approve(address(engine), amountDSCToBurn);
        engine.redeemCollateralForDSC(weth, amountCollateralToRedeem, amountDSCToBurn);

        assertEq(engine.getAmountCollateralDeposited(weth, USER), amountCollateralDeposited - amountCollateralToRedeem);
        assertEq(DSC.balanceOf(USER), amountDSCToMint - amountDSCToBurn);

        vm.stopPrank();
    }

    /**
     * @dev Test that the liquidation function works
     */
    function testLiquidationFailsIfHealthFactorGood() multiUser public {

        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        uint256 amountDSCToMint = 1.5e18;
        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited);
        engine.depositCollateralAndMint(weth, amountCollateralDeposited, amountDSCToMint);
        vm.stopPrank();

        vm.startPrank(USER2);
        vm.expectRevert(DSCEngine.DSCEngine__CannotLiquidateHealthyUser.selector);
        engine.liquidate(weth, USER, 1.5e18);
        vm.stopPrank();
    }

    function testLiquidationFailsIfOverLiquidating() multiUser public {

        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        uint256 amountDSCToMint = 1.5e18;
        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited);
        engine.depositCollateralAndMint(weth, amountCollateralDeposited, amountDSCToMint);
        vm.stopPrank();

        vm.startPrank(USER2);

        // Make weth less valuable
        MockV3Aggregator(wethPriceFeed).updateAnswer(1500e8);

        vm.expectRevert(DSCEngine.DSCEngine__NotEnoughDSCToBurn.selector);
        engine.liquidate(weth, USER, 1.6e18);
        vm.stopPrank();
    }

    function testLiquidationFailsIfWeakUser() multiUser public {

        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        uint256 amountDSCToMint = 1.5e18;
        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited);
        engine.depositCollateralAndMint(weth, amountCollateralDeposited, amountDSCToMint);
        vm.stopPrank();

        vm.startPrank(USER2);

        // Make weth less valuable
        MockV3Aggregator(wethPriceFeed).updateAnswer(1500e8);

        DSC.approve(address(engine), 1.5e18);

        vm.expectRevert();
        engine.liquidate(weth, USER, 1.5e18);
        vm.stopPrank();
    }

    function testLiquidationWorksIfUserHasDSC() multiUser public {

        vm.startPrank(USER);
        uint256 amountCollateralDeposited = 3e18 * PRECISION  / engine.getUSDPrice(wethPriceFeed);
        uint256 amountDSCToMint = 1.5e18;
        ERC20Mock(weth).approve(address(engine), amountCollateralDeposited);
        engine.depositCollateralAndMint(weth, amountCollateralDeposited, amountDSCToMint);
        vm.stopPrank();

        vm.startPrank(USER2);

        // Make weth less valuable
        uint256 USER2_DEPOSIT_AMOUNT = amountCollateralDeposited * 2;
        DSC.approve(address(engine), 1.5e18);

        ERC20Mock(weth).approve(address(engine), USER2_DEPOSIT_AMOUNT);
        engine.depositCollateralAndMint(weth, USER2_DEPOSIT_AMOUNT, amountDSCToMint);

        MockV3Aggregator(wethPriceFeed).updateAnswer(1500e8);

        uint256 LIQUIDATION_AMOUNT = 1.5e18;
        engine.liquidate(weth, USER, LIQUIDATION_AMOUNT);


        // Check that the liquidator gained the bonus
        uint256 amountOfCollateralTokens = engine.getTokenAmountFromUSD(LIQUIDATION_AMOUNT, weth);
        uint256 amountToGiveLiquidator = amountOfCollateralTokens * engine.getLiquidatorBonus() / 100;

        // Check the balance of the liquidator
        assertEq(ERC20Mock(weth).balanceOf(USER2), INITIAL_BALANCE - USER2_DEPOSIT_AMOUNT + amountToGiveLiquidator);

        // Check the collateral remaning in the vault
        assertEq(engine.getAmountCollateralDeposited(weth, USER), amountCollateralDeposited - amountToGiveLiquidator);
        vm.stopPrank();
    }

    /////////////////////
    //Constructor Tests//
    /////////////////////
    address[] tokens;
    address[] pricefeeds;

    function testRevertsOnMismatchedArrays() public {
        tokens.push(weth);
        pricefeeds.push(wethPriceFeed);
        tokens.push(wbtc);
        
        vm.expectRevert(DSCEngine.DSCEngine__NotMatchingTokensAndPriceFeeds.selector);
        new DSCEngine(tokens, pricefeeds, address(DSC)); // deploy a new DSCEngine, we expect a fail
    }
}
