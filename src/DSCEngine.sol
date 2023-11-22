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

pragma solidity ^0.8.18;

/*
* @title DSCEngine
* @author 0xjuaan
*
* The system is designed to be as minimal as possible, and have tokens maintain a 1 token == $1 peg.
* Properties include exogenous collateral (BTC, ETH), USD Pegged, Algorithmically Stable

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
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1;

    //////////
    //Events//
    //////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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

    function depositCollateralAndMint() external {}

    /* 
       @param tokenCollateralAddress: The address of the token to deposit as Collateral
       @param amountCollateral:       The amount of that token to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // Transfer their money now  
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    // Check if collateral value given > Value of DSC available

    /*
    @notice they must have more collateral value than the minimum threshold
    @param amount The amount of DSC to mint
     */

    function mintDSC(uint256 amount) 
    moreThanZero(amount)
    external {   
        s_DSCMinted[msg.sender] += amount;
        _revertBadHealthFactor(msg.sender);

        bool minted = i_DSC.mint(msg.sender, amount);
        if (!minted) {revert DSCEngine__MintFailed();}


    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor(address account) external view {

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

    function getUSDPrice(address priceFeedAddress) public view returns (uint256) {
       AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress);
       (,int256 USDPrice,,,) = priceFeed.latestRoundData();
       uint8 decimals = priceFeed.decimals();
       uint8 additionalPrecision = 18 - decimals;

       return uint256(USDPrice)*(10**additionalPrecision);
    }
    /* Private and internal view functions */

    
    function _getAccountInformation(address user) private view returns (uint256 totalDSCMinted, uint256 collateralValueInUSD) {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getTotalCollateralValue(user);
    }
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / 100; // due to LT, we pretty much value their collateral less. lower threshold = lower we value their collateral

        return (collateralAdjustedForThreshold * PRECISION /totalDSCMinted); // always maintain the 1e18 at the end of our actual number

    }

    function _revertBadHealthFactor(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorTooLow(healthFactor);
        }
    }
}
