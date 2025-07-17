// SPDX-License-Identifier: Business Source License 1.1
// First Release Time : 2025.03.30

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/islcoracle.sol";
import "./interfaces/iDecimals.sol";

import "./interfaces/iCoinFactory.sol";
import "./interfaces/iDepositOrLoanCoin.sol";
import "./interfaces/iLendingCoreAlgorithm.sol";
import "./interfaces/iLendingVaults.sol";

contract lendingManager  {
    using SafeERC20 for IERC20;

    uint public constant ONE_YEAR = 31536000;
    uint public constant UPPER_SYSTEM_LIMIT = 10000;

    uint    public slcUnsecuredIssuancesAmount;

    address public oracleAddr;
    address public coinFactory;
    address public lendingVault;
    address public coreAlgorithm;
    address public lendingInterface;

    address public setter;
    address newsetter;
    address public rebalancer;

    uint    public nomalFloorOfHealthFactor;
    uint    public homogeneousFloorOfHealthFactor;

    address public badDebtCollectionAddress;

    //  Assets Init:          USDT  USDC  BTC   ETH   0g
    //  MaximumLTV:            95%   95%  80%   75%  50%
    //  LiqPenalty:             3%    3%   4%    4%  10%
    //maxLendingAmountInRIM:     0     0    0     0   1k
    //bestLendingRatio:        76%   76%  70%   70%  50%
    //lendingModeNum:            2     2    4     5    3
    //homogeneousModeLTV:      97%   97%  95%   95%  60%
    //bestDepositInterestRate   4%    4%  4.5% 4.6%   6%


    struct licensedAsset{
        address assetAddr;             
        uint    maximumLTV;               // loan-to-value (LTV) ratio is a measurement lenders use to compare your loan amount 
                                          // for a home against the value of that property.(MAX = UPPER_SYSTEM_LIMIT) 
        uint    liquidationPenalty;       // MAX = UPPER_SYSTEM_LIMIT/5 ,default is 500(5%)
        uint    bestLendingRatio;         // MAX = UPPER_SYSTEM_LIMIT , setting NOT more than 9000
        uint    bestDepositInterestRate ; // MAX = UPPER_SYSTEM_LIMIT , setting NOT more than 1000
        uint    maxLendingAmountInRIM;    // default is 0, means no limits; if > 0, have limits : 1 ether = 1 slc
        uint    reserveFactor;            // default is 1000, (10%)
        uint8   lendingModeNum;           // Risk Isolation Mode: 1 ;  USDT  USDC : 2  ; 
        uint    homogeneousModeLTV;       // USDT  USDC : 97%  ; 
    }

    struct assetInfo{
        uint    latestDepositCoinValue;   // Relative to the initial DepositCoin value, the initial value is 1 ether
        uint    latestLendingCoinValue;   // Relative to the initial LendingCoin value, the initial value is 1 ether
        uint    latestDepositInterest;    // Latest interest value of DepositCoin
        uint    latestLendingInterest;    // Latest interest value of LendingCoin
        uint    latestTimeStamp;          // Latest TimeStamp
    }

    mapping(address => licensedAsset) public licensedAssets;
    mapping(address => address[2]) public assetsDepositAndLend;
    address[] public assetsSerialNumber;
    
    mapping(address => assetInfo) public assetInfos;
    mapping(address => mapping(address => uint)) public userRIMAssetsLendingNetAmount;
    mapping(address => uint) public riskIsolationModeLendingNetAmount; //RIM  Risk Isolation Mode
    mapping(address => address) public userRIMAssetsAddress; 
    address public riskIsolationModeAcceptAssets;
    mapping(address => uint8) public userMode; // High liquidity collateral mode:  0 ; 
                                               // Risk isolation mode              1 ;
                                               // homogeneousMode:                 2  USDT  USDC; 97% 3%

    //----------------------------modifier ----------------------------
    modifier onlySetter() {
        require(msg.sender == setter, 'Lending Manager: Only Setter Use');
        _;
    }

    //----------------------------- event -----------------------------
    event AssetsDeposit(address indexed tokenAddr, uint amount, address user);
    event WithdrawDeposit(address indexed tokenAddr, uint amount, address user);
    event LendAsset(address indexed tokenAddr, uint amount, address user);
    event RepayLoan(address indexed tokenAddr,uint amount, address user);
    event LicensedAssetsSetup(address indexed _asset, 
                                uint _maxLTV, 
                                uint _liqPenalty,
                                uint _maxLendingAmountInRIM, 
                                uint _bestLendingRatio, 
                                uint    reserveFactor,
                                uint8 _lendingModeNum,
                                uint _homogeneousModeLTV,
                                uint _bestDepositInterestRate) ;
    event UserModeSetting(address indexed user,uint8 _mode,address _userRIMAssetsAddress);
    event LendingInterfaceSetup(address indexed _interface);
    event FloorOfHealthFactorSetup(uint nomal, uint homogeneous);
    event DepositAndLoanInterest(address indexed token, 
                                 uint latestDepositInterest, 
                                 uint latestLoanInterest, 
                                 uint latestTimeStamp);
    event BadDebtDeduction(address user,uint blockTimestamp);
    //------------------------------------------------------------------

    constructor() {
        setter = msg.sender;
        rebalancer = msg.sender;
        nomalFloorOfHealthFactor = 1.2 ether;
        homogeneousFloorOfHealthFactor = 1.03 ether;
    }

    function setBadDebtCollectionAddress(address _badDebtCollectionAddress) external onlySetter{
        badDebtCollectionAddress = _badDebtCollectionAddress;
    }

    function transferSetter(address _set) external onlySetter{
        newsetter = _set;
    }
    function acceptSetter(bool _TorF) external {
        require(msg.sender == newsetter, 'Lending Manager: Permission FORBIDDEN');
        if(_TorF){
            setter = newsetter;
        }
        newsetter = address(0);
    }
    
    function setup( address _coinFactory,
                    address _lendingVault,
                    address _riskIsolationModeAcceptAssets,
                    address _coreAlgorithm,
                    address _oracleAddr ) external onlySetter{
        coinFactory = _coinFactory;
        oracleAddr = _oracleAddr;
        lendingVault = _lendingVault;
        coreAlgorithm = _coreAlgorithm;
        riskIsolationModeAcceptAssets = _riskIsolationModeAcceptAssets;
    }

    function updatelendingInterface(address _interface) external onlySetter{
        require(isContract(_interface),"Lending Manager: Interface MUST be a contract.");
        lendingInterface = _interface;
        emit LendingInterfaceSetup(_interface);
    }
    
    function setFloorOfHealthFactor(uint nomal, uint homogeneous) external onlySetter{
        nomalFloorOfHealthFactor = nomal;
        homogeneousFloorOfHealthFactor = homogeneous;
        emit FloorOfHealthFactorSetup( nomal, homogeneous);
    }

    function licensedAssetsRegister(address _asset, 
                                    uint  _maxLTV, 
                                    uint  _liqPenalty,
                                    uint  _maxLendingAmountInRIM, 
                                    uint  _bestLendingRatio, 
                                    uint  _reserveFactor,
                                    uint8 _lendingModeNum,
                                    uint  _homogeneousModeLTV,
                                    uint  _bestDepositInterestRate,
                                    bool  _isNew) public onlySetter {
        require(   _maxLTV < UPPER_SYSTEM_LIMIT
                && _liqPenalty <= UPPER_SYSTEM_LIMIT/5
                && _bestLendingRatio < UPPER_SYSTEM_LIMIT
                && _homogeneousModeLTV < UPPER_SYSTEM_LIMIT
                && _bestDepositInterestRate > 0
                && _bestDepositInterestRate < UPPER_SYSTEM_LIMIT,"Lending Manager: Exceed UPPER_SYSTEM_LIMIT");
        require(licensedAssets[_asset].assetAddr == address(0),"Lending Manager: Asset already registered!");
        assetsSerialNumber.push(_asset);
        if(_isNew){
            assetsDepositAndLend[_asset] = iCoinFactory(coinFactory).createDeAndLoCoin(_asset);
        }else{
            assetsDepositAndLend[_asset][0] = iCoinFactory(coinFactory).getDepositCoin(_asset);
            assetsDepositAndLend[_asset][1] = iCoinFactory(coinFactory).getLoanCoin(_asset);
        }
        require(assetsSerialNumber.length < 50,"Lending Manager: assets can't exceed 50");
        licensedAssets[_asset].assetAddr = _asset;
        licensedAssets[_asset].maximumLTV = _maxLTV;
        licensedAssets[_asset].liquidationPenalty = _liqPenalty;
        licensedAssets[_asset].maxLendingAmountInRIM = _maxLendingAmountInRIM;
        licensedAssets[_asset].bestLendingRatio = _bestLendingRatio;
        licensedAssets[_asset].lendingModeNum = _lendingModeNum;
        licensedAssets[_asset].homogeneousModeLTV = _homogeneousModeLTV;
        licensedAssets[_asset].bestDepositInterestRate = _bestDepositInterestRate;
        licensedAssets[_asset].reserveFactor = _reserveFactor;
        
        emit LicensedAssetsSetup(_asset, 
                                 _maxLTV, 
                                 _liqPenalty,
                                 _maxLendingAmountInRIM, 
                                 _bestLendingRatio, 
                                 _reserveFactor,
                                 _lendingModeNum,
                                 _homogeneousModeLTV,
                                 _bestDepositInterestRate) ;
    }

    function licensedAssetsReset(address _asset,
                                uint _maxLTV, 
                                uint _liqPenalty,
                                uint _maxLendingAmountInRIM, 
                                uint _bestLendingRatio, 
                                uint  _reserveFactor,
                                uint8 _lendingModeNum,
                                uint _homogeneousModeLTV,
                                uint _bestDepositInterestRate) public onlySetter {
        require(licensedAssets[_asset].assetAddr == _asset ,"Lending Manager: asset is Not registered!");
        require(   _maxLTV < UPPER_SYSTEM_LIMIT
                && _liqPenalty <= UPPER_SYSTEM_LIMIT/5
                && _bestLendingRatio < UPPER_SYSTEM_LIMIT
                && _homogeneousModeLTV < UPPER_SYSTEM_LIMIT
                && _bestDepositInterestRate > 0
                && _bestDepositInterestRate < UPPER_SYSTEM_LIMIT,"Lending Manager: Exceed UPPER_SYSTEM_LIMIT");
        licensedAssets[_asset].maximumLTV = _maxLTV;
        licensedAssets[_asset].liquidationPenalty = _liqPenalty;
        licensedAssets[_asset].maxLendingAmountInRIM = _maxLendingAmountInRIM;
        licensedAssets[_asset].bestLendingRatio = _bestLendingRatio;
        licensedAssets[_asset].lendingModeNum = _lendingModeNum;
        licensedAssets[_asset].homogeneousModeLTV = _homogeneousModeLTV;
        licensedAssets[_asset].bestDepositInterestRate = _bestDepositInterestRate;
        licensedAssets[_asset].reserveFactor = _reserveFactor;
        emit LicensedAssetsSetup(_asset, 
                                 _maxLTV, 
                                 _liqPenalty,
                                 _maxLendingAmountInRIM, 
                                 _bestLendingRatio, 
                                 _reserveFactor,
                                 _lendingModeNum,
                                 _homogeneousModeLTV,
                                 _bestDepositInterestRate) ;
    }

    function userModeSetting(uint8 _mode,address _userRIMAssetsAddress, address user) public {
        if(lendingInterface != msg.sender){
            require(user == msg.sender,"Lending Manager: Not slcInterface or user need be msg.sender!");
        }
        require(_userTotalLendingValue(user) == 0 && _userTotalDepositValue(user) == 0,"Lending Manager: should return all Lending Assets and withdraw all Deposit Assets.");

        if(_mode == 1){
            require(licensedAssets[_userRIMAssetsAddress].maxLendingAmountInRIM > 0,"Lending Manager: Mode 1 Need a RIMAsset.");
        }

        userMode[user] = _mode;
        userRIMAssetsAddress[user] = _userRIMAssetsAddress;
        emit UserModeSetting(user, _mode, _userRIMAssetsAddress);
    }

    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != accountHash);
    }
    //     licensedAssets[_asset].assetAddr = _asset;
    //     licensedAssets[_asset].maximumLTV = _maxLTV;
    //     licensedAssets[_asset].liquidationPenalty = _liqPenalty;
    //     licensedAssets[_asset].maxLendingAmountInRIM = _maxLendingAmountInRIM;
    //     licensedAssets[_asset].bestLendingRatio = _bestLendingRatio;
    //     licensedAssets[_asset].lendingModeNum = _lendingModeNum;
    //     licensedAssets[_asset].homogeneousModeLTV = _homogeneousModeLTV;
    //     licensedAssets[_asset].bestDepositInterestRate = _bestDepositInterestRate;
    //     assetsDepositAndLend[_asset] = iCoinFactory(coinFactory).createDeAndLoCoin(_asset);

    //----------------------------- View Function------------------------------------
    function assetsBaseInfo(address token) public view returns(uint maximumLTV,
                                                               uint liquidationPenalty,
                                                               uint maxLendingAmountInRIM,
                                                               uint bestLendingRatio,
                                                               uint lendingModeNum,
                                                               uint homogeneousModeLTV,
                                                               uint bestDepositInterestRate){
        return (licensedAssets[token].maximumLTV,
                licensedAssets[token].liquidationPenalty,
                licensedAssets[token].maxLendingAmountInRIM,
                licensedAssets[token].bestLendingRatio,
                licensedAssets[token].lendingModeNum,
                licensedAssets[token].homogeneousModeLTV,
                licensedAssets[token].bestDepositInterestRate);
    }
    function assetsreserveFactor(address token) public view returns(uint reserveFactor){
        return (licensedAssets[token].reserveFactor);
    }

    function assetsTimeDependentParameter(address token) public view returns(uint latestDepositCoinValue,
                                                                             uint latestLendingCoinValue,
                                                                             uint latestDepositInterest,
                                                                             uint latestLendingInterest){
        return (assetInfos[token].latestDepositCoinValue,
                assetInfos[token].latestLendingCoinValue,
                assetInfos[token].latestDepositInterest,
                assetInfos[token].latestLendingInterest);
    }

    function assetsDepositAndLendAddrs(address token) external view returns(address[2] memory addrs){
        return assetsDepositAndLend[token];
    }

    function licensedAssetAmount() public view returns(uint assetLength){
        assetLength = assetsSerialNumber.length;
    }

    function _userTotalLendingValue(address _user) internal view returns(uint values){
        //require(assetsSerialNumber.length < 100,"Lending Manager: Too Much assets");
        for(uint i=0;i<assetsSerialNumber.length;i++){
            values += IERC20(assetsDepositAndLend[assetsSerialNumber[i]][1]).balanceOf(_user) 
            * iSlcOracle(oracleAddr).getPrice(assetsSerialNumber[i]) / 1 ether;
        }
    }
    function _userTotalDepositValue(address _user) internal view returns(uint values){
        //require(assetsSerialNumber.length < 100,"Lending Manager: Too Much assets");
        for(uint i=0;i!=assetsSerialNumber.length;i++){
            values += IERC20(assetsDepositAndLend[assetsSerialNumber[i]][0]).balanceOf(_user) 
            * iSlcOracle(oracleAddr).getPrice(assetsSerialNumber[i]) / 1 ether;
        }
    }

    function userDepositAndLendingValue(address user) public view returns(uint _amountDeposit,uint _amountLending){
        //require(assetsSerialNumber.length < 100,"Lending Manager: Too Much assets");
        uint tempgetprice;
        for(uint i=0;i!=assetsSerialNumber.length;i++){
            tempgetprice = iSlcOracle(oracleAddr).getPrice(assetsSerialNumber[i]);
            if(userMode[user]>1){
                    _amountDeposit += iDepositOrLoanCoin(assetsDepositAndLend[assetsSerialNumber[i]][0]).balanceOf(user)
                                    * tempgetprice / 1 ether
                                    * licensedAssets[assetsSerialNumber[i]].homogeneousModeLTV / UPPER_SYSTEM_LIMIT;
            }else{
                    _amountDeposit += iDepositOrLoanCoin(assetsDepositAndLend[assetsSerialNumber[i]][0]).balanceOf(user)
                                    * tempgetprice / 1 ether
                                    * licensedAssets[assetsSerialNumber[i]].maximumLTV / UPPER_SYSTEM_LIMIT;
            }
            _amountLending += iDepositOrLoanCoin(assetsDepositAndLend[assetsSerialNumber[i]][1]).balanceOf(user)
                                * tempgetprice / 1 ether;
        }
        
    }

    function viewUsersHealthFactor(address user) public view returns(uint userHealthFactor){
        uint _amountDeposit;
        uint _amountLending;

        (_amountDeposit,_amountLending) = userDepositAndLendingValue(user);
        if(_amountLending > 0){
            userHealthFactor = _amountDeposit * 1 ether / _amountLending;
        }else if(_amountDeposit >= 0){
            userHealthFactor = 1000 ether;
        }else{
            userHealthFactor = 0 ether;
        }
    }

    // 1 year = 31,536,000 s
    function getCoinValues(address token) public view returns(uint[2] memory currentValue){
        uint tempVaule = (block.timestamp - assetInfos[token].latestTimeStamp) * 1 ether / (ONE_YEAR * UPPER_SYSTEM_LIMIT);
        currentValue[0] = assetInfos[token].latestDepositCoinValue 
                        + tempVaule * assetInfos[token].latestDepositInterest;
        currentValue[1] = assetInfos[token].latestLendingCoinValue 
                        + tempVaule * assetInfos[token].latestLendingInterest;

        if(currentValue[0] == 0){
            currentValue[0] = 1 ether;
        }
        if(currentValue[1] == 0){
            currentValue[1] = 1 ether;
        }

    }

    function userAssetOverview(address user) public view returns(address[] memory tokens, uint[] memory _amountDeposit, uint[] memory _amountLending){
        uint assetLength = assetsSerialNumber.length;
        _amountDeposit = new uint[](assetLength);
        _amountLending = new uint[](assetLength);
        tokens = new address[](assetLength);
        for(uint i=0;i!=assetLength;i++){
            tokens[i] = assetsSerialNumber[i];
            _amountDeposit[i] = iDepositOrLoanCoin(assetsDepositAndLend[assetsSerialNumber[i]][0]).balanceOf(user);
            _amountLending[i] = iDepositOrLoanCoin(assetsDepositAndLend[assetsSerialNumber[i]][1]).balanceOf(user);
        }
    }

    //---------------------------- borrow & lend  Function----------------------------
    // struct assetInfo{
    //     uint    latestDepositCoinValue;
    //     uint    latestLendingCoinValue;
    //     uint    latestDepositInterest;
    //     uint    latestLendingInterest;
    //     uint    latestTimeStamp;
    // }
    function _beforeUpdate(address token) internal returns(uint[2] memory latestValues){
        latestValues = getCoinValues(token);
        assetInfos[token].latestDepositCoinValue = latestValues[0];
        assetInfos[token].latestLendingCoinValue = latestValues[1];
        assetInfos[token].latestTimeStamp = block.timestamp;

    }
    
    function _assetsValueUpdate(address token) internal returns(uint[2] memory latestInterest){
        require(assetInfos[token].latestTimeStamp == block.timestamp,"Lending Manager: Only be uesd after beforeUpdate");
        latestInterest = iLendingCoreAlgorithm(coreAlgorithm).assetsValueUpdate(token);
        assetInfos[token].latestDepositInterest = latestInterest[0];
        assetInfos[token].latestLendingInterest = latestInterest[1];
        emit DepositAndLoanInterest( token, latestInterest[0], latestInterest[1], block.timestamp);
        
    }

    //  Assets Deposit
    function assetsDeposit(address tokenAddr, uint amount, address user) public  {
        uint amountNormalize = amount * 1 ether / (10**iDecimals(tokenAddr).decimals());
        if(lendingInterface != msg.sender){
            require(user == msg.sender,"Lending Manager: Not slcInterface or user need be msg.sender!");
        }
        require(amount > 0,"Lending Manager: Cant Pledge 0 amount");
        if(userMode[user] == 0){
            require(licensedAssets[tokenAddr].maxLendingAmountInRIM == 0,"Lending Manager: Wrong Token in Risk Isolation Mode");
        }else if(userMode[user] == 1){
            require((tokenAddr == userRIMAssetsAddress[user]),"Lending Manager: Wrong Token in Risk Isolation Mode");
        }else {
            require((licensedAssets[tokenAddr].lendingModeNum == userMode[user]),"Lending Manager: Wrong Mode, Need in same homogeneous Mode");
        }

        _beforeUpdate(tokenAddr);
        IERC20(tokenAddr).safeTransferFrom(msg.sender,lendingVault,amount);
        iDepositOrLoanCoin(assetsDepositAndLend[tokenAddr][0]).mintCoin(user,amountNormalize);
        _assetsValueUpdate(tokenAddr);
        emit AssetsDeposit(tokenAddr, amount, user);
    
    }

    // Withdrawal of deposits
    function withdrawDeposit(address tokenAddr, uint amount, address user) public  {
        uint amountNormalize = amount * 1 ether / (10**iDecimals(tokenAddr).decimals());
        if(lendingInterface != msg.sender){
            require(user == msg.sender,"Lending Manager: Not slcInterface or user need be msg.sender!");
        }
        require(amount > 0,"Lending Manager: Cant Pledge 0 amount");
        // There is no need to check the mode

        iLendingVaults(lendingVault).vaultsERC20Approve(tokenAddr, amount);
        _beforeUpdate(tokenAddr);
        IERC20(tokenAddr).safeTransferFrom(lendingVault,msg.sender,amount);
        iDepositOrLoanCoin(assetsDepositAndLend[tokenAddr][0]).burnCoin(user,amountNormalize);
        _assetsValueUpdate(tokenAddr);
        
        uint factor;
        (factor) = viewUsersHealthFactor(user);
        if(userMode[user] > 1){
            require( factor >= homogeneousFloorOfHealthFactor,"Your Health Factor <= homogeneous Floor Of Health Factor, Cant redeem assets");
        }else{
            require( factor >= nomalFloorOfHealthFactor,"Your Health Factor <= nomal Floor Of Health Factor, Cant redeem assets");
        }
        emit WithdrawDeposit(tokenAddr, amount, user);
    
    }

    // lend Asset
    function lendAsset(address tokenAddr, uint amount, address user) public  {
        uint amountNormalize = amount * 1 ether / (10**iDecimals(tokenAddr).decimals());

        if(lendingInterface != msg.sender){
            require(user == msg.sender,"Lending Manager: Not slcInterface or user need be msg.sender!");
        }
        require(amount > 0,"Lending Manager: Cant Pledge 0 amount");

        if(userMode[user] == 1){
            require(tokenAddr == riskIsolationModeAcceptAssets,"Lending Manager: Wrong Token in Risk Isolation Mode");
            uint tempAmount = IERC20(assetsDepositAndLend[riskIsolationModeAcceptAssets][1]).balanceOf(user) + amountNormalize;
            riskIsolationModeLendingNetAmount[tokenAddr] = riskIsolationModeLendingNetAmount[tokenAddr] 
                                                         - userRIMAssetsLendingNetAmount[user][tokenAddr]
                                                         + tempAmount;
            userRIMAssetsLendingNetAmount[user][tokenAddr] = tempAmount;
            require(riskIsolationModeLendingNetAmount[tokenAddr] <= licensedAssets[userRIMAssetsAddress[user]].maxLendingAmountInRIM,"Lending Manager: Deposit Amount exceed limits");
        }
        if(userMode[user] > 1){
            require((licensedAssets[tokenAddr].lendingModeNum == userMode[user]),"Lending Manager: Wrong Mode, Need in same homogeneous Mode");
        }
        _beforeUpdate(tokenAddr);
        iDepositOrLoanCoin(assetsDepositAndLend[tokenAddr][1]).mintCoin(user,amountNormalize);
        iLendingVaults(lendingVault).vaultsERC20Approve(tokenAddr, amount);
        IERC20(tokenAddr).safeTransferFrom(lendingVault,msg.sender,amount);
        _assetsValueUpdate(tokenAddr);

        uint factor;
        (factor) = viewUsersHealthFactor(user);
        if(userMode[user] > 1){
            require( factor >= homogeneousFloorOfHealthFactor,"Your Health Factor <= homogeneous Floor Of Health Factor, Cant redeem assets");
        }else{
            require( factor >= nomalFloorOfHealthFactor,"Your Health Factor <= nomal Floor Of Health Factor, Cant redeem assets");
        }
        // assetsDepositAndLend[token]
        require(IERC20(assetsDepositAndLend[tokenAddr][0]).totalSupply() * 99 / 100 >= IERC20(assetsDepositAndLend[tokenAddr][1]).totalSupply(),"Lending Manager: total amount borrowed can t exceeds 99% of the deposit");
        emit LendAsset(tokenAddr, amount, user);
    
    }

    // repay Loan
    function repayLoan(address tokenAddr,uint amount, address user) public  {
        uint amountNormalize = amount * 1 ether / (10**iDecimals(tokenAddr).decimals());

        if(lendingInterface != msg.sender){
            require(user == msg.sender,"Lending Manager: Not slcInterface or user need be msg.sender!");
        }
        require(amount > 0,"Lending Manager: Cant Pledge 0 amount");

        if(userMode[user] == 1){
            require(licensedAssets[userRIMAssetsAddress[user]].maxLendingAmountInRIM > 0,"Lending Manager: Wrong Token in Risk Isolation Mode");
            require((tokenAddr == riskIsolationModeAcceptAssets),"Lending Manager: Wrong Token in Risk Isolation Mode");
            uint tempAmount = IERC20(assetsDepositAndLend[riskIsolationModeAcceptAssets][1]).balanceOf(user) - amountNormalize;
            riskIsolationModeLendingNetAmount[tokenAddr] = riskIsolationModeLendingNetAmount[tokenAddr] 
                                                         - userRIMAssetsLendingNetAmount[user][tokenAddr]
                                                         + tempAmount;
            userRIMAssetsLendingNetAmount[user][tokenAddr] = tempAmount;
        }
        _beforeUpdate(tokenAddr);
        iDepositOrLoanCoin(assetsDepositAndLend[tokenAddr][1]).burnCoin(user,amountNormalize);
        IERC20(tokenAddr).safeTransferFrom(msg.sender,lendingVault,amount);
        _assetsValueUpdate(tokenAddr);
        emit RepayLoan(tokenAddr, amount, user);
    }
    //------------------------------------------------------------------------------
    function badDebtDeduction(address user) public {
        require(_userTotalDepositValue(user) <= _userTotalLendingValue(user)*102/100,"Lending Manager: should be bad debt.");
        for(uint i=0;i!=assetsSerialNumber.length;i++){
            if(IERC20(assetsDepositAndLend[assetsSerialNumber[i]][0]).balanceOf(user)>0){
                iDepositOrLoanCoin(assetsDepositAndLend[assetsSerialNumber[i]][0]).mintCoin(badDebtCollectionAddress,IERC20(assetsDepositAndLend[assetsSerialNumber[i]][0]).balanceOf(user));
            }
            if(IERC20(assetsDepositAndLend[assetsSerialNumber[i]][1]).balanceOf(user)>0){
                iDepositOrLoanCoin(assetsDepositAndLend[assetsSerialNumber[i]][1]).mintCoin(badDebtCollectionAddress,IERC20(assetsDepositAndLend[assetsSerialNumber[i]][1]).balanceOf(user));
            }
            if(IERC20(assetsDepositAndLend[assetsSerialNumber[i]][0]).balanceOf(user)>0){
                iDepositOrLoanCoin(assetsDepositAndLend[assetsSerialNumber[i]][0]).burnCoin(user,IERC20(assetsDepositAndLend[assetsSerialNumber[i]][0]).balanceOf(user));
            }
            if(IERC20(assetsDepositAndLend[assetsSerialNumber[i]][1]).balanceOf(user)>0){
                iDepositOrLoanCoin(assetsDepositAndLend[assetsSerialNumber[i]][1]).burnCoin(user,IERC20(assetsDepositAndLend[assetsSerialNumber[i]][1]).balanceOf(user));
            } 
        }
        emit BadDebtDeduction(user,block.timestamp);
    }

    //------------------------------ Liquidate Function------------------------------
    // token Liquidate
    function tokenLiquidate(address user,
                            address liquidateToken,
                            uint    liquidateAmount, 
                            address depositToken) public returns(uint usedAmount) {
        uint liquidateAmountNormalize = liquidateAmount * 1 ether / (10**iDecimals(liquidateToken).decimals());
        _beforeUpdate(liquidateToken);
        _beforeUpdate(depositToken);

        require(liquidateAmountNormalize > 0,"Lending Manager: Cant Pledge 0 amount");
        
        require(viewUsersHealthFactor(user) < 1 ether,"Lending Manager: Users Health Factor Need < 1 ether");
        uint amountLending = iDepositOrLoanCoin(assetsDepositAndLend[liquidateToken][0]).balanceOf(user);
        uint amountDeposit = iDepositOrLoanCoin(assetsDepositAndLend[depositToken][1]).balanceOf(user);
        require( amountLending >= liquidateAmountNormalize,"Lending Manager: amountLending >= liquidateAmountNormalize");//Ensure that the liquidation quantity does not exceed the balance of the assets of the liquidated users

        usedAmount = liquidateAmountNormalize * iSlcOracle(oracleAddr).getPrice(liquidateToken);//Convert liquidation amount to liquidation amount * price
        usedAmount = usedAmount * (UPPER_SYSTEM_LIMIT - licensedAssets[liquidateToken].liquidationPenalty)
                                / (UPPER_SYSTEM_LIMIT * iSlcOracle(oracleAddr).getPrice(depositToken));//Convert the settlement amount into the number of user debt tokens, and deduct the user incentive for liquidationPenalty here
        require( amountDeposit >= usedAmount,"Lending Manager: amountDeposit >= usedAmount");//Ensure that the number of deposited tokens deducted from liquidationPenalty by users is not greater than their outstanding debts
        
        iDepositOrLoanCoin(assetsDepositAndLend[liquidateToken][0]).burnCoin(user,liquidateAmountNormalize);
        iDepositOrLoanCoin(assetsDepositAndLend[depositToken][1]).burnCoin(user,usedAmount);
        
        usedAmount = usedAmount * (10**iDecimals(depositToken).decimals()) / 1 ether;

        iLendingVaults(lendingVault).vaultsERC20Approve(liquidateToken, liquidateAmount);
        IERC20(depositToken).safeTransferFrom(msg.sender, lendingVault, usedAmount);
        IERC20(liquidateToken).safeTransferFrom(lendingVault, msg.sender, liquidateAmount);
        
        _assetsValueUpdate(liquidateToken);
        _assetsValueUpdate(depositToken);
        emit AssetsDeposit(liquidateToken, liquidateAmount, user);
        emit RepayLoan(depositToken, usedAmount, user);
    }
    
    function tokenLiquidateEstimate(address user,
                            address liquidateToken,
                            address depositToken) public view returns(uint[2] memory maxAmounts){
        if(viewUsersHealthFactor(user) >= 1 ether){
            uint[2] memory zero;
            return zero;
        }
        uint amountliquidate = iDepositOrLoanCoin(assetsDepositAndLend[liquidateToken][0]).balanceOf(user);
        uint amountDeposit = iDepositOrLoanCoin(assetsDepositAndLend[depositToken][1]).balanceOf(user);
        uint liquidateTokenPrice = iSlcOracle(oracleAddr).getPrice(liquidateToken);
        uint depositTokenPrice = iSlcOracle(oracleAddr).getPrice(depositToken);

        uint liquidateMaxValue = amountliquidate * liquidateTokenPrice / 1 ether;//
        uint depositMaxValue = amountDeposit * depositTokenPrice / 1 ether
                      * UPPER_SYSTEM_LIMIT / (UPPER_SYSTEM_LIMIT - licensedAssets[liquidateToken].liquidationPenalty);//

        if(liquidateMaxValue < depositMaxValue){
            maxAmounts[0] = amountliquidate;
            maxAmounts[1] = liquidateMaxValue * (UPPER_SYSTEM_LIMIT - licensedAssets[liquidateToken].liquidationPenalty) * 1 ether 
                                            / (UPPER_SYSTEM_LIMIT * depositTokenPrice);
        }else if(liquidateMaxValue == depositMaxValue){
            maxAmounts[0] = amountliquidate;
            maxAmounts[1] = amountDeposit;
        }else{
            maxAmounts[0] = depositMaxValue * 1 ether / liquidateTokenPrice;//At this point, this Token deposit of the liquidated user will be fully liquidated
            maxAmounts[1] = amountDeposit;
            
        }
        maxAmounts[0] = maxAmounts[0] * (10**iDecimals(depositToken).decimals()) / 1 ether;
        maxAmounts[1] = maxAmounts[1] * (10**iDecimals(depositToken).decimals()) / 1 ether;
    }
}