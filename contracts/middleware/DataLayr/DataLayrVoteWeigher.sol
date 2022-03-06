// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/MiddlewareInterfaces.sol";
import "../../interfaces/CoreInterfaces.sol";
import "../../interfaces/InvestmentInterfaces.sol";
import "../../interfaces/DataLayrInterfaces.sol";
import "../QueryManager.sol";


contract DataLayrVoteWeigher is IVoteWeighter, IRegistrationManager {
    IInvestmentManager public investmentManager;
    //consensus layer ETH counts for 'consensusLayerPercent'/100 when compared to ETH deposited in the system itself
    IEigenLayrDelegation public delegation;
    uint256 public consensusLayerPercent = 10;
    // Data Layr Nodes
    struct Registrant {
        string socket; // how people can find it
        uint32 id; // id is always unique
        uint256 index; // corresponds to registrantList
        uint32 from;
        uint48 fromDumpNumber;
        uint32 to;
        bool active; //bool
    }

    event Registration(
        uint8 typeEvent, // 0: addedMember, 1: leftMember
        uint32 initiator, // who started
        uint32 numRegistrant
    );

    IQueryManager public queryManager;
    uint32 public latestTime;

    // Register, everyone is active in the list
    mapping(address => Registrant) public registry;
    address[] public registrantList;
    uint32 public numRegistrant;
    uint32 public nextRegistrantId;
    uint256 public dlnStake = 1 wei;
    
    constructor(IInvestmentManager _investmentManager, IEigenLayrDelegation _delegation){
        investmentManager = _investmentManager;
        delegation = _delegation;
    }

    function setQueryManager(IQueryManager _queryManager) public {
        require(
            address(queryManager) == address(0),
            "Query Manager already set"
        );
        queryManager = _queryManager;
    }

    function setDlnStake(uint256 _dlnStake) public {
        require(
            address(queryManager) == msg.sender,
            "Query Manager can only change stake"
        );
        dlnStake = _dlnStake;
    }

    function setLatestTime(uint32 _latestTime) public {
        require(
            address(queryManager.feeManager()) == msg.sender,
            "Fee manager can only call this"
        );
        latestTime = _latestTime;
    }

    function weightOfOperator(address operator) public returns(uint256) {
        return delegation.getConsensusLayerEthDelegated(operator) * consensusLayerPercent / 100 + delegation.getUnderlyingEthDelegated(operator);
    }

    // Registration and ETQ

    function operatorPermitted(address operator, bytes calldata socket_) public returns(bool) {
        require(!registry[operator].active, "Operator is already registered");
        require(weightOfOperator(operator) > dlnStake, "Not enough staked");
        registry[operator] = Registrant({
            socket: string(socket_),
            id: nextRegistrantId,
            index: queryManager.numRegistrants(),
            active: true,
            from: uint32(block.timestamp),
            fromDumpNumber: IDataLayrServiceManager(address(queryManager.feeManager())).dumpNumber(),
            to: 0
        });
        registrantList.push(operator);

        emit Registration(0, registry[operator].id, 0);
        return true;
    }

    function commitDeregistration() public returns(bool) {
        require(registry[msg.sender].active, "Operator is already registered");
        registry[msg.sender].to = latestTime;
        registry[msg.sender].active = true;
        emit Registration(1, registry[msg.sender].id, 0);
        return true;
    }

    function operatorPermittedToLeave(address operator, bytes calldata socket_) public view returns(bool) {
        require(registry[operator].to != 0 || registry[operator].to < block.timestamp, "Operator is already registered");
        return true;
    }

    function getOperatorFromDumpNumber(address operator) public view returns(uint48) {
        return registry[operator].fromDumpNumber;
    }
    
}