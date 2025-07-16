// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


contract rewardRecordMock{
    struct userUpdateInfo{
        uint latestTimeStamp;             
        uint userSelectedTypesAcountValue;    
    }
    //----------------------Persistent Variables ----------------------
    address public setPermissionAddress;
    address newPermissionAddress;

    // address[] public rewardRegistAddr;

    // address1 is user address;
    // address2 is coin/contract address;
    // userUpdateInfo is the updated info of user in this coin/contract address
    mapping(address => mapping(address => userUpdateInfo)) public userSelectedTypesAcountInfo;//
    mapping(address => uint) public selectedTypesAcountSum;//
    mapping(address => uint) public tokenOrVaultType;

    mapping(address => bool) public updateAddress;

    //----------------------------- modifier -----------------------------
    modifier onlyPermissionAddress() {
        require(setPermissionAddress == msg.sender, 'Coin Factory: Permission FORBIDDEN');
        _;
    }
    modifier updateLicensed() {
        require(updateAddress[msg.sender], 'Coin Factory: update Not Licensed');
        _;
    }
    //------------------------------- event ------------------------------

    event SetPA(address newPermissionAddress);
    event AcceptPA(bool _TorF);
    event SetUpdateAddress(address _updateAddress, bool _TorF);

    //--------------------------- Setup functions --------------------------
    function setPA(address _setPermissionAddress) external onlyPermissionAddress{
        newPermissionAddress = _setPermissionAddress;
        emit SetPA(_setPermissionAddress);
    }
    function acceptPA(bool _TorF) external {
        require(msg.sender == newPermissionAddress, 'X Swap Factory: Permission FORBIDDEN');
        if(_TorF){
            setPermissionAddress = newPermissionAddress;
        }
        newPermissionAddress = address(0);
        emit AcceptPA(_TorF);
    }
    function setUpdateAddress(address _updateAddress, bool _TorF) external onlyPermissionAddress{
        updateAddress[_updateAddress] = _TorF;
        emit SetUpdateAddress(_updateAddress, _TorF);
    }

    //---------------------------------------------------------------------

    function recordUpdate(address _userAccount,uint _value) external  returns(bool){
        // only msg.sender == record address
        selectedTypesAcountSum[msg.sender] = selectedTypesAcountSum[msg.sender]
                                           + _value
                                           - userSelectedTypesAcountInfo[_userAccount][msg.sender].userSelectedTypesAcountValue;

        userSelectedTypesAcountInfo[_userAccount][msg.sender].userSelectedTypesAcountValue = _value;
        userSelectedTypesAcountInfo[_userAccount][msg.sender].latestTimeStamp = block.timestamp;
        
        return true;
    }
    function factoryUsedRegist(address _token, uint256 _type) external returns(bool){
        //only factory or administrators
        tokenOrVaultType[_token] = _type;
        return true;
    }
}
