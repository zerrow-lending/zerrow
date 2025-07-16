// SPDX-License-Identifier: Business Source License 1.1
// First Release Time : 2024.09.30

pragma solidity 0.8.6;

interface iLendingCoreAlgorithm  {
    
    function assetsValueUpdate(address token) external view returns(uint[2] memory latestInterest);

    function depositInterestRate(address token,uint lendingRatio) external view returns(uint _rate);
    function lendingInterestRate(address token,uint lendingRatio, uint reserveFactor) external view returns(uint _rate);

}