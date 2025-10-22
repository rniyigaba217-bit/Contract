// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title School Funding Transparency Contract
 * @dev A blockchain-based system for transparent distribution and tracking of school funds.
 * Roles: Ministry (admin), Schools, and Parents/Students (optional fee payments)
 */

contract SchoolFunding {

    address public ministry; // The admin (government/ministry)
    uint public totalSchools;

    struct School {
        string name;
        address wallet;
        uint allocatedFunds;
        uint receivedFunds;
        bool isRegistered;
    }

    mapping(address => School) public schools;
    mapping(address => uint) public studentFees;

    event SchoolRegistered(string name, address wallet);
    event FundsAllocated(address indexed school, uint amount);
    event FundsReleased(address indexed school, uint amount);
    event FeePaid(address indexed student, uint amount);
    event FundWithdrawal(address indexed ministry, uint amount);

    modifier onlyMinistry() {
        require(msg.sender == ministry, "Only ministry can perform this action");
        _;
    }

    modifier onlyRegisteredSchool(address _school) {
        require(schools[_school].isRegistered, "School not registered");
        _;
    }

    constructor() {
        ministry = msg.sender;
    }

    // ✅ Ministry registers a new school
    function registerSchool(string memory _name, address _wallet) public onlyMinistry {
        require(!schools[_wallet].isRegistered, "School already registered");
        schools[_wallet] = School(_name, _wallet, 0, 0, true);
        totalSchools++;
        emit SchoolRegistered(_name, _wallet);
    }

    // ✅ Allocate funds for a school
    function allocateFunds(address _school) public payable onlyMinistry onlyRegisteredSchool(_school) {
        require(msg.value > 0, "Must allocate some funds");
        schools[_school].allocatedFunds += msg.value;
        emit FundsAllocated(_school, msg.value);
    }

    // ✅ School withdraws allocated funds
    function releaseFunds(address payable _school, uint _amount)
        public
        onlyMinistry
        onlyRegisteredSchool(_school)
    {
        require(schools[_school].allocatedFunds >= _amount, "Insufficient allocated funds");
        schools[_school].allocatedFunds -= _amount;
        schools[_school].receivedFunds += _amount;
        _school.transfer(_amount);

        emit FundsReleased(_school, _amount);
    }

    // ✅ Optional: Students/parents pay school fees transparently
    function payFees(address _school) public payable onlyRegisteredSchool(_school) {
        require(msg.value > 0, "Payment cannot be zero");
        studentFees[msg.sender] += msg.value;
        schools[_school].receivedFunds += msg.value;
        emit FeePaid(msg.sender, msg.value);
    }

    // ✅ Check school info
    function getSchoolInfo(address _school) public view returns (
        string memory name,
        uint allocatedFunds,
        uint receivedFunds
    ) {
        School memory s = schools[_school];
        return (s.name, s.allocatedFunds, s.receivedFunds);
    }

    // ✅ Ministry can withdraw remaining funds (if needed)
    function withdraw(uint _amount) public onlyMinistry {
        require(address(this).balance >= _amount, "Insufficient contract balance");
        payable(ministry).transfer(_amount);
        emit FundWithdrawal(ministry, _amount);
    }

    // ✅ Contract balance
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }
}
