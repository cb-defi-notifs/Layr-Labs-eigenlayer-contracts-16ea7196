// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/IQueryManager.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IInvestmentManager.sol";
import "../../libraries/BytesLib.sol";
import "../QueryManager.sol";

contract DataLayrVoteWeigher is IVoteWeighter, IRegistrationManager {
    using BytesLib for bytes;
    IInvestmentManager public investmentManager;
    //consensus layer ETH counts for 'consensusLayerPercent'/100 when compared to ETH deposited in the system itself
    IEigenLayrDelegation public delegation;
    uint256 public constant consensusLayerPercent = 10;
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
    uint32 public nextRegistrantId;
    uint128 public dlnEthStake = 1 wei;
    uint128 public dlnEigenStake = 1 wei;

    mapping(uint48 => bytes32) public eigenStakeHashes;
    uint48[] public eigenStakeHashUpdates;
    mapping(uint48 => bytes32) public ethStakeHashes;
    uint48[] public ethStakeHashUpdates;

    constructor(
        IInvestmentManager _investmentManager,
        IEigenLayrDelegation _delegation
    ) {
        investmentManager = _investmentManager;
        delegation = _delegation;
    }

    modifier onlyQMGovernance() {
        require(
            queryManager.timelock() == msg.sender,
            "Query Manager governance can only call this function"
        );
        _;
    }

    function setQueryManager(IQueryManager _queryManager) public {
        require(
            address(queryManager) == address(0),
            "Query Manager already set"
        );
        queryManager = _queryManager;
    }

    function weightOfOperatorEigen(address operator)
        public
        view
        returns (uint128)
    {
        uint128 eigenAmount = uint128(delegation.getEigenDelegated(operator));
        return eigenAmount < dlnEigenStake ? 0 : eigenAmount;
    }

    function weightOfOperatorEth(address operator) public returns (uint128) {
        uint128 amount = uint128(
            delegation.getConsensusLayerEthDelegated(operator) /
                queryManager.consensusLayerEthToEth() +
                delegation.getUnderlyingEthDelegated(operator)
        );
        return amount < dlnEthStake ? 0 : amount;
    }

    // Registration and ETQ
    // Data is structured as such:
    // uint8 registrantType,
    //      uint256 ethStakeLength, uint32 index, bytes ethStakes
    //      or/and
    //      uint256 eigenStakeLength, uint32 index, bytes eigenStakes,
    //      uint8 socketLength, bytes[socketLength] socket
    function registerOperator(address operator, bytes calldata data)
        public
        returns (uint8, uint128)
    {
        require(
            registry[operator].active == 0,
            "Operator is already registered"
        );
        //get the first byte of data
        uint8 registrantType = data.toUint8(0);
        //length of socket in bytes
        uint256 socketLengthPointer = 37;
        uint128 eigenAmount;
        if (registrantType == 1) {
            // if they want to be an "eigen" validator, check that they meet the eigen requirements
            eigenAmount = weightOfOperatorEigen(operator);
            require(eigenAmount >= dlnEigenStake, "Not enough eigen staked");
            //parse and update eigen stakes
            address[] memory operators = new address[](1);
            uint32[] memory indexes = new uint32[](1);
            operators[0] = operator;
            indexes[0] = data.toUint32(33);
            uint256 eigenStakesLength = data.toUint256(2);
            //increment socket length pointer
            socketLengthPointer += eigenStakesLength;
            updateEigenStakes(data.slice(37, eigenStakesLength), operators, indexes);
        } else if (registrantType == 2) {
            // if they want to be an "eth" validator, check that they meet the eth requirements
            require(
                weightOfOperatorEth(operator) >= dlnEthStake,
                "Not enough eth value staked"
            );
            //parse and update eigen stakes
            address[] memory operators = new address[](1);
            uint32[] memory indexes = new uint32[](1);
            operators[0] = operator;
            indexes[0] = data.toUint32(33);
            uint256 ethStakesLength = data.toUint256(2);
            //increment socket length pointer
            socketLengthPointer += ethStakesLength;
            updateEthStakes(data.slice(37, ethStakesLength), operators, indexes);
        } else if (registrantType == 3) {
            // if they want to be an "eigen and eth" validator, check that they meet the eigen and eth requirements
            eigenAmount = weightOfOperatorEigen(operator);
            require(
                eigenAmount >= dlnEigenStake &&
                    weightOfOperatorEth(operator) >= dlnEthStake,
                "Not enough eth value or eigen staked"
            );
            //parse and update eth and eigen stakes
            address[] memory operators = new address[](1);
            uint32[] memory indexes = new uint32[](1);
            operators[0] = operator;
            indexes[0] = data.toUint32(33);
            uint256 stakesLength = data.toUint256(2);
            //increment socket length pointer
            socketLengthPointer += stakesLength;
            updateEthStakes(data.slice(37, stakesLength), operators, indexes);
            //now do it for eigen stuff
            indexes[0] = data.toUint32(socketLengthPointer + 32);
            stakesLength = data.toUint256(socketLengthPointer);
            //increment socket length pointer
            socketLengthPointer += stakesLength;
            updateEigenStakes(data.slice(37, stakesLength), operators, indexes);
        } else {
            revert("Invalid registrant type");
        }
        // everything but the first byte of data is their socket
        // get current dump number from fee manager
        registry[operator] = Registrant({
            socket: string(data.slice(2, data.toUint8(socketLengthPointer) - 1)),
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

    //stakes must be of the form
    //address,uint128,address,uint128
    function updateEthStakes(
        bytes memory stakes,
        address[] memory operators,
        uint32[] memory indexes
    ) public {
        //stakes must be preimage of last update's hash
        require(keccak256(stakes) == ethStakeHashes[ethStakeHashUpdates[ethStakeHashUpdates.length - 1]], "Stakes are incorrect");
        require(
            indexes.length == operators.length,
            "operator len and index len don't match"
        );
        uint256 len = operators.length;
        for (uint i = 0; i < len; ) {
            uint128 newEth = uint128(
                delegation.getUnderlyingEthDelegated(operators[i]) +
                    delegation.getConsensusLayerEthDelegated(operators[i]) /
                    queryManager.consensusLayerEthToEth()
            );
            uint256 start = uint256(indexes[i] * 36);
            //36 bytes per person: 20 for address, 16 for stake
            require(
                stakes.toAddress(indexes[i] * 36) == operators[i],
                "index is incorrect"
            );
            //replace stake with new eth stake
            stakes = stakes
                .slice(0, indexes[i] * 36 + 20)
                .concat(abi.encodePacked(uint256(newEth)))
                .concat(
                    stakes.slice(
                        indexes[i] * 36 + 36,
                        stakes.length - 1 - indexes[i] * 36 + 36
                    )
                );
            unchecked {
                ++i;
            }
        }
        //get dump number from dlsm
        uint48 currDumpNumber = IDataLayrServiceManager(address(queryManager.feeManager())).dumpNumber();
        ethStakeHashUpdates.push(currDumpNumber);
        ethStakeHashes[currDumpNumber] = keccak256(stakes);
    }

    //stakes must be of the form
    //address,uint128,address,uint128
    function updateEigenStakes(
        bytes memory stakes,
        address[] memory operators,
        uint32[] memory indexes
    ) public {
        //stakes must be preimage of last update's hash
        require(keccak256(stakes) == eigenStakeHashes[eigenStakeHashUpdates[eigenStakeHashUpdates.length - 1]], "Stakes are incorrect");
        require(
            indexes.length == operators.length,
            "operator len and index len don't match"
        );
        uint256 len = operators.length;
        for (uint i = 0; i < len; ) {
            uint128 newEigen = weightOfOperatorEigen(operators[i]);
            uint256 start = uint256(indexes[i] * 36);
            //36 bytes per person: 20 for address, 16 for stake
            require(
                stakes.toAddress(indexes[i] * 36) == operators[i],
                "index is incorrect"
            );
            //replace stake with new eigen stake
            stakes = stakes
                .slice(0, indexes[i] * 36 + 20)
                .concat(abi.encodePacked(uint256(newEigen)))
                .concat(
                    stakes.slice(
                        indexes[i] * 36 + 36,
                        stakes.length - 1 - indexes[i] * 36 + 36
                    )
                );
            unchecked {
                ++i;
            }
        }
        //get dump number from dlsm
        uint48 currDumpNumber = IDataLayrServiceManager(address(queryManager.feeManager())).dumpNumber();
        eigenStakeHashUpdates.push(currDumpNumber);
        eigenStakeHashes[currDumpNumber] = keccak256(stakes);
    }

    function getOperatorFromDumpNumber(address operator)
        public
        view
        returns (uint48)
    {
        return registry[operator].fromDumpNumber;
    }

    function setDlnEigenStake(uint128 _dlnEigenStake) public {
        require(
            queryManager.timelock() == msg.sender,
            "Query Manager can only change stake"
        );
        dlnEigenStake = _dlnEigenStake;
    }

    function setDlnEthStake(uint128 _dlnEthStake) public {
        require(
            queryManager.timelock() == msg.sender,
            "Query Manager can only change stake"
        );
        dlnEthStake = _dlnEthStake;
    }

    function setLatestTime(uint32 _latestTime) public {
        require(
            address(queryManager.feeManager()) == msg.sender,
            "Fee manager can only call this"
        );
        latestTime = _latestTime;
    }

    function getOperatorId(address operator) public view returns (uint32) {
        return registry[operator].id;
    }

    function getEthStakesHashUpdate(uint256 index) public returns(uint256) {
        return ethStakeHashUpdates[index];
    }

    function getEigenStakesHashUpdate(uint256 index) public returns(uint256) {
        return eigenStakeHashUpdates[index];
    }

    function getEthStakesHashUpdateAndCheckIndex(uint256 index, uint48 dumpNumber) public returns(bytes32) {
        uint48 dumpNumberAtIndex = ethStakeHashUpdates[index];
        require(dumpNumberAtIndex <= dumpNumber, "DumpNumber at index is not less than or equal dumpNumber");
        if(index != ethStakeHashUpdates.length - 1) {
            require(ethStakeHashUpdates[index + 1] > dumpNumber, "DumpNumber at index is not less than or equal dumpNumber");
        }
        return ethStakeHashes[dumpNumberAtIndex];
    }

    function getEigenStakesHashUpdateAndCheckIndex(uint256 index, uint48 dumpNumber) public returns(bytes32) {
        uint48 dumpNumberAtIndex = eigenStakeHashUpdates[index];
        require(dumpNumberAtIndex <= dumpNumber, "DumpNumber at index is not less than or equal dumpNumber");
        if(index != eigenStakeHashUpdates.length - 1) {
            require(eigenStakeHashUpdates[index + 1] > dumpNumber, "DumpNumber at index is not less than or equal dumpNumber");
        }
        return eigenStakeHashes[dumpNumberAtIndex];
    }
}
