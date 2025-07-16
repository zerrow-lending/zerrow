// SPDX-License-Identifier: Business Source License 1.1
// First Release Time : 2024.09.30

pragma solidity 0.8.6;
interface iLstGimo{
    // function getPrice(address Token) external view returns (uint price);
    function stake(string calldata _memo) external payable;
    function unstake(uint256 _lsdTokenAmount) external;
    function getRate() external view returns (uint256);

}