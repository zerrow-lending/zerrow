// SPDX-License-Identifier: Business Source License 1.1
// First Release Time : 2025.03.30

pragma solidity 0.8.6;
import "./interfaces/iLendingManager.sol";
import "./interfaces/iDepositOrLoanCoin.sol";

contract lendingCoreAlgorithm  {
    address public lendingManager;

    constructor(address _setLendingManager) {
        lendingManager = _setLendingManager;
    }
    struct assetInfo{
        uint    latestDepositCoinValue;
        uint    latestLendingCoinValue;
        uint    latestDepositInterest;
        uint    latestLendingInterest;
    }
    function assetsValueUpdate(address token) public view returns(uint[2] memory latestInterest){
        uint reserveFactor = iLendingManager(lendingManager).assetsreserveFactor( token);
        require(reserveFactor > 0,"core: reserveFactor Must > 0");
        address[2] memory depositAndLend = iLendingManager(lendingManager).assetsDepositAndLendAddrs(token);
        uint lendingRatio;
        uint[2] memory tempTotalSupply;
        tempTotalSupply[0] = iDepositOrLoanCoin(depositAndLend[0]).totalSupply();
        tempTotalSupply[1] = iDepositOrLoanCoin(depositAndLend[1]).totalSupply();

        if(tempTotalSupply[0] > 0){
            lendingRatio = tempTotalSupply[1] * 10000 / tempTotalSupply[0] ;
        }else{
            lendingRatio = 0;
        }
        
        if(lendingRatio > 10000){
            lendingRatio = 10000;
        }
        latestInterest[0] = depositInterestRate( token, lendingRatio);
        latestInterest[1] = lendingInterestRate( token, lendingRatio, reserveFactor);
    }

    function assetsBaseInfo(address token) internal view returns(uint maximumLTV,
                                                               uint bestLendingRatio,
                                                               uint lendingModeNum,
                                                               uint bestDepositInterestRate){
        (maximumLTV,,,bestLendingRatio,lendingModeNum,,bestDepositInterestRate) = iLendingManager(lendingManager).assetsBaseInfo(token);
    }

    function depositInterestRate(address token,uint lendingRatio) public view returns(uint _rate){
        uint[4] memory info;
        (info[0],info[1],info[2],info[3]) = assetsBaseInfo(token);
        uint bestLendingRatio = info[1];
        if(lendingRatio > 9400){
            _rate = (info[3] * lendingRatio / bestLendingRatio) * lendingRatio / bestLendingRatio
                  * (lendingRatio - bestLendingRatio)  / 500
                  * (lendingRatio - 9300) / 100;
        }else if(lendingRatio > bestLendingRatio + 500){
            _rate = (info[3] * lendingRatio / bestLendingRatio) * lendingRatio / bestLendingRatio
                  * (lendingRatio - bestLendingRatio)  / 500;
        }else {
            _rate = (info[3] * lendingRatio / bestLendingRatio) * lendingRatio / bestLendingRatio;
        }
    }
    function lendingInterestRate(address token,uint lendingRatio, uint reserveFactor) public view returns(uint _rate){
        uint[4] memory info;
        (info[0],info[1],info[2],info[3]) = assetsBaseInfo(token);
        uint bestLendingRatio = info[1];

        if(lendingRatio > 9400){
            _rate = (info[3] * lendingRatio / bestLendingRatio) * (10000 + reserveFactor) / bestLendingRatio  
                  * (lendingRatio - bestLendingRatio)  / 500 * lendingRatio / (bestLendingRatio +500)
                  * (lendingRatio - 9300) * (lendingRatio - 9300)/ 10000;
        }else if(lendingRatio > bestLendingRatio + 500){
            _rate = (info[3] * lendingRatio / bestLendingRatio) * (10000 + reserveFactor) / bestLendingRatio  
                  * (lendingRatio - bestLendingRatio)  / 500 * lendingRatio / (bestLendingRatio +500);
        }else {
            _rate = (info[3] * lendingRatio / bestLendingRatio) * (10000 + reserveFactor) / bestLendingRatio ;
        }
    }

}