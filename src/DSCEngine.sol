// SPDX-License-Identifier: MIT

/*LAYOUT*/

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions


/* 
Invariants for this contract: 
    When liquidating someone, your healthfactor should stay > 1
    



*/

pragma solidity ^0.8.18;

/*
* @title DSCEngine
* @author 0xjuaan
*
* The system is designed to be as minimal as possible, and have tokens maintain a 1 token == $1 peg.
* Properties include 1. exogenous collateral (BTC, ETH), 2. USD Pegged, 3. Algorithmically Stable

* Similar to DAI, but only backed by wETH and wBTC, and no fees
*
* The DSC system should always higher collateral value than DSC value in the system
*
* @notice This contract is the core of the DSC system. It handles all logic for minting, depositing, and withdrawing collateral. 
*/

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/Test.sol";

contract DSCEngine is ReentrancyGuard {
    //////////
    //Errors//
    //////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__NotMatchingTokensAndPriceFeeds();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorTooLow(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__CannotLiquidateHealthyUser();
    error DSCEngine__NotEnoughDSCToBurn();
    error DSCEngine__HealthFactorNotImproved();
    ///////////////////
    //State Variables//
    ///////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;

    DecentralisedStableCoin i_DSC;
    address[] private s_collateralTokens;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_BONUS = 110;

    //////////
    //Events//
    //////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event redeemed(address indexed user, address indexed tokenAddress, uint256 indexed amountCollateralRedeemed);

    /////////////
    //Modifiers//
    /////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /////////////
    //Functions//
    /////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address DSCAddress) {
        
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__NotMatchingTokensAndPriceFeeds();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);

        }

        i_DSC = DecentralisedStableCoin(DSCAddress);
    }

    //////////////////////
    //External Functions//
    //////////////////////

    function depositCollateralAndMint(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /* 
       @param tokenCollateralAddress: The address of the token to deposit as Collateral
       @param amountCollateral:       The amount of that token to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {

        // Update storage data
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // Transfer their money now  
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
    

    /*
    @param collateralTokenAddress: The token address of collateral to redeem
    @param amountCollateral: the amount of collateral to redeem

    This Function redeems collateral, and reverts if this makes their health factor too low after the redemption
    */
    function redeemCollateral(address collateralTokenAddress, uint256 amountCollateral) 
    public
    moreThanZero(amountCollateral)
    nonReentrant 
    {
        _redeemCollateral(collateralTokenAddress, amountCollateral, msg.sender, msg.sender);
    }

    /* This function burns DSC that has been minted prior */
    function burnDSC(uint256 amount) 
    public
    moreThanZero(amount)
    {
        _burnDSC(amount, msg.sender, msg.sender);
    }

    /*
    @param collateralTokenAddress: The token address of collateral to redeem
    @param amountCollateral: the amount of collateral to redeem
    @param: amountDSCToBurn: the amount of DSC token to burn

    This Function burns DSC and redeems collateral afterwards
    */
    function redeemCollateralForDSC(
        address collateralTokenAddress, uint256 amountCollateral, uint256 amountDSCToBurn
        ) 
    external 
    {
        burnDSC(amountDSCToBurn);
        redeemCollateral(collateralTokenAddress, amountCollateral); 
    }   


    // Check if collateral value given > Value of DSC available

    /*
    @notice they must have more collateral value than the minimum threshold
    @param amount The amount of DSC to mint
     */
    function mintDSC(uint256 amount) 
    moreThanZero(amount)
    public 
    {   
        s_DSCMinted[msg.sender] += amount;
        _revertBadHealthFactor(msg.sender);

        bool minted = i_DSC.mint(msg.sender, amount);
        if (!minted) {revert DSCEngine__MintFailed();}
    }

    /* 
        This function allows a user to liquidate the DSC of another user, if their health factor is below the minimum
        If the system is overcollateralized, then the liquidator will receive a bonus

        @param collateralTokenAddress: The token address of collateral to redeem
        @param userToLiquidate: the address of the user to liquidate
            @notice this user must have a health factor below the minimum 
        @param amount: the amount of collateral to redeem
    */
    function liquidate(address collateralTokenAddress, address userToLiquidate, uint256 amount) external {

        uint256 healthFactorBefore = _healthFactor(userToLiquidate);
        if (healthFactorBefore >= MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__CannotLiquidateHealthyUser();
        }

        // Since they are unhealthy, lets liquidate them (burn their debt, take their collateral)
        uint256 amountDSC = s_DSCMinted[userToLiquidate];

        if (amount > amountDSC) {revert DSCEngine__NotEnoughDSCToBurn();} // trying to burn too much DSC
        _burnDSC(amountDSC, userToLiquidate, msg.sender); 

        // Now lets redeem their collateral
        // First we gotta find out how much of that collateralToken we need, based on the DSC value that was burned
        uint256 amountOfCollateralTokens = getTokenAmountFromUSD(amount, collateralTokenAddress);   

        // We dont give it all to the liquidator, we give a set bonus of 10% (obviously this is crappy if the system is less than 110% collateralized) 
        uint256 amountToGiveToLiquidator = (amountOfCollateralTokens * LIQUIDATOR_BONUS) / 100;
        // Now send that money to the liquidator
        _redeemCollateral(collateralTokenAddress, amountToGiveToLiquidator, userToLiquidate, msg.sender);

        uint256 healthFactorAfter = _healthFactor(userToLiquidate);
        if (healthFactorAfter <= healthFactorBefore) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        // Also make sure that the liquidator's health factor is still good
        // The liquidaator's health factor should only improve, since they are getting more collateral while burning DSC
        _revertBadHealthFactor(msg.sender);
    }

    

    function getTotalCollateralValue(address user) public view returns (uint256)  {
        
        uint256 totalValue = 0;

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            address priceFeedAddress = s_priceFeeds[token];

            uint256 tokenPrice = getUSDPrice(priceFeedAddress);
            totalValue += (amount * tokenPrice / PRECISION);
        }

        return totalValue;
    }

    // Uses pricefeed 
    function getUSDPrice(address priceFeedAddress) public view returns (uint256) {
       AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
       (,int256 USDPrice,,,) = priceFeed.latestRoundData();
       uint8 decimals = priceFeed.decimals();
       uint8 additionalPrecision = 18 - decimals;

       return uint256(USDPrice)*(10**additionalPrecision);
    }

    /* Private functions */

    function _redeemCollateral(
        address collateralTokenAddress, 
        uint256 amountCollateral, 
        address from, 
        address to
    ) private {
        // First do the accounting
        s_collateralDeposited[from][collateralTokenAddress] -= amountCollateral;
        emit redeemed(from, collateralTokenAddress, amountCollateral);

        // Then do the ting
        bool success = IERC20(collateralTokenAddress).transfer(to, amountCollateral);
        if (!success) {revert DSCEngine__TransferFailed();}

        // Then check
        _revertBadHealthFactor(from);
    }

    function _burnDSC(uint256 amount, address onBehalfOf, address DSCFrom) 
    private
    moreThanZero(amount)
    {
        // If onBehalfOf != DSCFrom, then we are paying off someone else's loan. otherwise we are paying off our own loan

        s_DSCMinted[onBehalfOf] -= amount; // ? check that they have enough ? actually: seems like it causes an underflow error so we good
        bool success = i_DSC.transferFrom(DSCFrom, address(this), amount);
        if (!success) {revert DSCEngine__TransferFailed();} // technically we shouldnt reach this since transferFrom handles errors (Openzeppelin made it for us)

        // Now call the burn function in DSC
        i_DSC.burn(amount);
    }
    /* Private and internal view functions */


    function getTokenAmountFromUSD(uint256 amount, address tokenAddress) public view returns (uint256) {
        uint256 tokenPrice = getUSDPrice(s_priceFeeds[tokenAddress]);
        return (amount * PRECISION / tokenPrice);
    }

    
    function _getAccountInformation(address user) private view returns (uint256 totalDSCMinted, uint256 collateralValueInUSD) {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getTotalCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);

        if (totalDSCMinted == 0) {
            // return the max integer
            return type(uint256).max;
        }

        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / 100; // due to 50% LT, we pretty much value their collateral less. lower threshold = lower we value their collateral
        return (collateralAdjustedForThreshold * PRECISION / totalDSCMinted); // always maintain the 1e18 at the end of our actual number

    }

    function _revertBadHealthFactor(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorTooLow(healthFactor);
        }
    }

    /* External View functions */
    function getAmountCollateralDeposited(address token, address user) external view returns(uint256) {
        return s_collateralDeposited[user][token];
    }

    function getHealthFactor(address account) external view returns(uint256) {
        return _healthFactor(account);
    }

    function getDSCAmount(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getLiquidatorBonus()  external pure returns (uint256) {
        return LIQUIDATOR_BONUS;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

}
