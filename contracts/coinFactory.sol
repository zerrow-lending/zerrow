// SPDX-License-Identifier: Business Source License 1.1
// First Release Time : 2025.03.30
pragma solidity 0.8.6;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import './template/depositOrLoanCoin.sol';
import "./interfaces/iRewardMini.sol";

contract coinFactory  {
    //----------------------Persistent Variables ----------------------
    address public setPermissionAddress;
    address newPermissionAddress;
    address public lendingManager;
    address public rewardContract;
    uint public depositType;
    uint public loanType;
    mapping(address => address) public getDepositCoin;
    mapping(address => address) public getLoanCoin;

    //-------------------------- constructor --------------------------
    constructor(address _setPermissionAddress) {
        setPermissionAddress = _setPermissionAddress;
    }

    //----------------------------- event -----------------------------
    event DepositCoinCreated(address indexed token, address DepositCoin);
    event LoanCoinCreatedX(address indexed token, address LoanCoin);
    //----------------------------- functions -----------------------------
    function createDeAndLoCoin(address token) external returns (address[2] memory _pAndLCoin) {
        require(msg.sender == lendingManager, 'Coin Factory: msg.sender MUST be lendingManager.');
        require(token != address(0), 'Coin Factory: ZERO_ADDRESS');
        require(getDepositCoin[token] == address(0), 'Coin Factory: COIN_EXISTS');// single check is sufficient
        require(lendingManager != address(0), 'Coin Factory: Coin manager NOT Set');
        require(rewardContract != address(0), 'Coin Factory: Reward Contract NOT Set');
        require(depositType != 0, 'Coin Factory: Reward Type NOT Set');
        bytes32 _salt1 = keccak256(abi.encodePacked(token,msg.sender, "Deposit Coin"));
        bytes32 _salt2 = keccak256(abi.encodePacked(token,msg.sender, "Loan Coin"));
        // Only ERC20 Tokens Can create pairs
        _pAndLCoin[0] = address(new depositOrLoanCoin{salt: _salt1}(0,token,lendingManager, rewardContract, strConcat(string(ERC20(token).symbol()), " Deposit Coin"),strConcat(string(ERC20(token).symbol()), " DCoin")));  //
        _pAndLCoin[1] = address(new depositOrLoanCoin{salt: _salt2}(1,token,lendingManager, rewardContract,strConcat(string(ERC20(token).symbol()), " Loan Coin"),strConcat(string(ERC20(token).symbol()), " LCoin"))); 
        getDepositCoin[token] = _pAndLCoin[0];
        getLoanCoin[token] = _pAndLCoin[1];
        iRewardMini(rewardContract).factoryUsedRegister(_pAndLCoin[0], depositType);
        iRewardMini(rewardContract).factoryUsedRegister(_pAndLCoin[1], loanType);
        emit DepositCoinCreated( token, _pAndLCoin[0]);
        emit LoanCoinCreatedX( token, _pAndLCoin[1]);
    }

    function strConcat(string memory _str1, string memory _str2) internal pure returns (string memory) {
        return string(abi.encodePacked(_str1, _str2));
    }
    function name(address token) public view returns (string memory) {
        return string(ERC20(token).name());
    }

    //--------------------------- Setup functions --------------------------


    function settings(address _lendingManager,address _rewardContract) external {
        require(msg.sender == setPermissionAddress, 'Coin Factory: Permission FORBIDDEN');
        // vaults = _vault;
        lendingManager = _lendingManager;
        rewardContract = _rewardContract;
    }

    function coinResetup(address coinAddr,address _rewardContract) external{
        require(msg.sender == setPermissionAddress, 'Coin Factory: Permission FORBIDDEN');
        // depositOrLoanCoin(coinAddr).managerSetup(_manager);
        depositOrLoanCoin(coinAddr).rewardContractSetup(_rewardContract);
    }
    function rewardTypeSetup(uint _depositType,uint _loanType) external{
        require(msg.sender == setPermissionAddress, 'Coin Factory: Permission FORBIDDEN');
        require(_depositType * _loanType > 0, 'Coin Factory: Type Must > 0');
        require(_depositType != _loanType, 'Coin Factory: depositType and loanType Must NOT same');
        require(_depositType > 0 && _depositType <= 10000,"Coin Factory: Invalid deposit type");
        require(_loanType > 0 && _loanType <= 10000,"Coin Factory: Invalid loan type");
        depositType = _depositType;
        loanType = _loanType;
    }

    function setPA(address _setPermissionAddress) external {
        require(msg.sender == setPermissionAddress, 'Coin Factory: Permission FORBIDDEN');
        require(_setPermissionAddress != address(0),'Coin Factory: Zero Address Not Allowed');
        newPermissionAddress = _setPermissionAddress;
    }
    function acceptPA(bool _TorF) external {
        require(msg.sender == newPermissionAddress, 'Coin Factory: Permission FORBIDDEN');
        if(_TorF){
            setPermissionAddress = newPermissionAddress;
        }
        newPermissionAddress = address(0);
    }

}
