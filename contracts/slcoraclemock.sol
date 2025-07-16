// SPDX-License-Identifier: Business Source License 1.1
// First Release Time : 2024.09.30

pragma solidity 0.8.6;

contract slcOracleMock{
    mapping(address => uint) public tokenprice;

    function setPrice(address token, uint price) external{
        tokenprice[token] = price;
    }

    function getPrice(address token) external view returns (uint price){
        return tokenprice[token];
    }
}