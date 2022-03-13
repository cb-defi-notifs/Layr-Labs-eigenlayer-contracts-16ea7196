// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IQueryManager.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IInvestmentManager.sol";
import "../../libraries/BytesLib.sol";
import "../../interfaces/DataLayrInterfaces.sol";
import "../QueryManager.sol";


contract DataLayrVoteWeigher is IVoteWeighter, IRegistrationManager {
    using BytesLib for bytes;
    IInvestmentManager public investmentManager;
    //consensus layer ETH counts for 'consensusLayerPercent'/100 when compared to ETH deposited in the system itself
    IEigenLayrDelegation public delegation;
    uint256 public consensusLayerPercent = 10;
    // Data Layr Nodes
    struct Registrant {
        string socket; // how people can find it
        uint32 id; // id is always unique
        uint64 index; // corresponds to registrantList
        uint48 fromDumpNumber;
        uint32 to;
        uint8 active; //bool
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
    uint256 public dlnEthStake = 1 wei;
    uint256 public dlnEigenStake = 1 wei;

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

    function setDlnStake(uint256 _dlnEthStake, uint256 _dlnEigenStake) public {
        require(
            address(queryManager) == msg.sender,
            "Query Manager can only change stake"
        );
        dlnEthStake = _dlnEthStake;
        dlnEigenStake = _dlnEigenStake;
    }

    function setLatestTime(uint32 _latestTime) public {
        require(
            address(queryManager.feeManager()) == msg.sender,
            "Fee manager can only call this"
        );
        latestTime = _latestTime;
    }

    function weightOfOperatorEigen(address operator) public returns(uint256) {
        return delegation.getEigenDelegated(operator);
    }

    function weightOfOperatorEth(address operator) public returns(uint256) {
        return delegation.getConsensusLayerEthDelegated(operator) * consensusLayerPercent / 100 + delegation.getUnderlyingEthDelegated(operator);
    }

    // Registration and ETQ

    function registerOperator(address operator, bytes calldata data) public returns(uint8) {
        require(registry[operator].active == 0, "Operator is already registered");
        uint8 registrantType = data.toUint8(0);
        if(registrantType == 1) {
            require(weightOfOperatorEigen(operator) >= dlnEigenStake, "Not enough eigen staked");
        } else if (registrantType == 2) {
            require(weightOfOperatorEth(operator) >= dlnEthStake, "Not enough eth value staked");
        } else if(registrantType == 3) {
            require(weightOfOperatorEigen(operator) >= dlnEigenStake && weightOfOperatorEth(operator) >= dlnEthStake, "Not enough eth value or eigen staked");
        }else {
            revert("Invalid registrant type");
        }
        registry[operator] = Registrant({
            socket: string(data.slice(1, data.length - 1)),
            id: nextRegistrantId,
            index: uint64(queryManager.numRegistrants()),
            active: registrantType,
            fromDumpNumber: IDataLayrServiceManager(address(queryManager.feeManager())).dumpNumber(),
            to: 0
        });
        registrantList.push(operator);
        nextRegistrantId++;
        emit Registration(0, registry[operator].id, 0);
        return registrantType;
    }

    function commitDeregistration() public returns(bool) {
        require(registry[msg.sender].active > 0, "Operator is already registered");
        registry[msg.sender].to = latestTime;
        registry[msg.sender].active = 0;
        emit Registration(1, registry[msg.sender].id, 0);
        return true;
    }

    function deregisterOperator(address operator, bytes calldata) public view returns(bool) {
        require(registry[operator].to != 0 || registry[operator].to < block.timestamp, "Operator is already registered");
        return true;
    }

    function getOperatorFromDumpNumber(address operator) public view returns(uint48) {
        return registry[operator].fromDumpNumber;
    }  
}