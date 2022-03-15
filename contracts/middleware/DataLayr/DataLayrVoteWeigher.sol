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

    constructor(
        IInvestmentManager _investmentManager,
        IEigenLayrDelegation _delegation
    ) {
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

    function weightOfOperatorEigen(address operator) public returns (uint256) {
        uint256 eigenAmount = delegation.getEigenDelegated(operator);
        return eigenAmount < dlnEigenStake ? 0 : eigenAmount;
    }

    function weightOfOperatorEth(address operator) public returns (uint256) {
        uint256 amount = (delegation.getConsensusLayerEthDelegated(operator) *
            consensusLayerPercent) /
            100 +
            delegation.getUnderlyingEthDelegated(operator);
        return amount < dlnEthStake ? 0 : amount;
    }

    // Registration and ETQ

    function registerOperator(address operator, bytes calldata data)
        public
        returns (uint8, uint256)
    {
        require(
            registry[operator].active == 0,
            "Operator is already registered"
        );
        //get the first byte of data
        uint8 registrantType = data.toUint8(0);
        uint256 eigenAmount;
        if (registrantType == 1) {
            // if they want to be an "eigen" validator, check that they meet the eigen requirements
            eigenAmount = weightOfOperatorEigen(operator);
            require(eigenAmount >= dlnEigenStake, "Not enough eigen staked");
        } else if (registrantType == 2) {
            // if they want to be an "eth" validator, check that they meet the eth requirements
            require(
                weightOfOperatorEth(operator) >= dlnEthStake,
                "Not enough eth value staked"
            );
        } else if (registrantType == 3) {
            // if they want to be an "eigen and eth" validator, check that they meet the eigen and eth requirements
            eigenAmount = weightOfOperatorEigen(operator);
            require(
                eigenAmount >= dlnEigenStake &&
                    weightOfOperatorEth(operator) >= dlnEthStake,
                "Not enough eth value or eigen staked"
            );
        } else {
            revert("Invalid registrant type");
        }
        // everything but the first byte of data is their socket
        // get current dump number from fee manager
        registry[operator] = Registrant({
            socket: string(data.slice(1, data.length - 1)),
            id: nextRegistrantId,
            index: uint64(queryManager.numRegistrants()),
            active: registrantType,
            fromDumpNumber: IDataLayrServiceManager(
                address(queryManager.feeManager())
            ).dumpNumber(),
            to: 0
        });

        registrantList.push(operator);
        nextRegistrantId++;
        emit Registration(0, registry[operator].id, 0);
        return (registrantType, eigenAmount);
    }

    function commitDeregistration() public returns (bool) {
        require(
            registry[msg.sender].active > 0,
            "Operator is already registered"
        );
        // they must store till the latest time a dump expires
        registry[msg.sender].to = latestTime;
        // but they will not sign off on any more dumps
        registry[msg.sender].active = 0;
        emit Registration(1, registry[msg.sender].id, 0);
        return true;
    }

    function deregisterOperator(address operator, bytes calldata)
        public
        view
        returns (bool)
    {
        require(
            registry[operator].to != 0 ||
                registry[operator].to < block.timestamp,
            "Operator is already registered"
        );
        return true;
    }

    function getOperatorFromDumpNumber(address operator)
        public
        view
        returns (uint48)
    {
        return registry[operator].fromDumpNumber;
    }
}
