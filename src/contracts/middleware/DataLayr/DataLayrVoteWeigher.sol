// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IQueryManager.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IInvestmentManager.sol";
import "../../libraries/BytesLib.sol";
import "../QueryManager.sol";

/**
 * @notice 
 */

contract DataLayrVoteWeigher is IVoteWeighter, IRegistrationManager {
    using BytesLib for bytes;

    IInvestmentManager public investmentManager;

    IEigenLayrDelegation public delegation;

    /**
     * @notice  Details on DataLayr nodes that would be used for - 
     *           - sending data by the sequencer
     *           - querying by any challenger/retriever
     *           - payment and associated challenges    
     */
    struct Registrant {
        // id is always unique
        uint32 id; 

        // corresponds to registrantList
        uint64 index; 

        // 
        uint48 fromDumpNumber;
        uint32 to;

        uint8 active; //bool

        // socket address of the DataLayr node 
        string socket; 
    }


    /** 
     * @notice pack two uint128's into a storage slot
     */
    struct Uint128xUint128 {
        uint128 a;
        uint128 b;
    }


    // EVENT
    /**
     * @notice 
     */
    event Registration();

    event DeregistrationCommit(
        address registrant // who started
    );

    event EthStakeAdded(address, uint128);
    event EigenStakeAdded(address, uint128);
    event EthStakeUpdate(address, uint128);
    event EigenStakeUpdate(address, uint128);


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

        //TODO: make sure this works!
        //initialize the ETH and EIGEN stakes
        eigenStakeHashUpdates.push(0);
        ethStakeHashUpdates.push(0);
        bytes memory zero;
        bytes32 zeroHash = keccak256(zero);
        eigenStakeHashes[0] = zeroHash;
        ethStakeHashes[0] = zeroHash;
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

    /**
     * @notice returns the total Eigen delegated by delegators with this operator 
     */
    /**
     * @dev minimum delegation limit has to be satisfied.
     */ 
    function weightOfOperatorEigen(address operator)
        public
        view
        returns (uint128)
    {
        uint128 eigenAmount = uint128(delegation.getEigenDelegated(operator));

        // check that minimum delegation limit is satisfied
        return eigenAmount < dlnEigenStake ? 0 : eigenAmount;
    }


    /**
     * @notice returns the total ETH delegated by delegators with this operator. 
     */
    /**
     * @dev Accounts for both ETH used for staking in settlement layer (via operator)
     *      and the ETH-denominated value of the shares in the investment strategies.
     *      Note that the DataLayr can decide for itself how much weight it wants to 
     *      give to the ETH that is being used for staking in settlement layer.    
     */
    function weightOfOperatorEth(address operator) public returns (uint128) {
        uint128 amount = uint128(
            delegation.getConsensusLayerEthDelegated(operator) /
                queryManager.consensusLayerEthToEth() +
                delegation.getUnderlyingEthDelegated(operator)
        );

        // check that minimum delegation limit is satisfied
        return amount < dlnEthStake ? 0 : amount;
    }

    // Registration and ETQ
    // Data is structured as such:
    // uint8 registrantType,
    //      uint256 ethStakeLength, bytes ethStakes
    //      or/and
    //      uint256 eigenStakeLength, bytes eigenStakes,
    //      uint8 socketLength, bytes[socketLength] socket

    /**
     * @notice Used for registering a new validator with DataLayr. 
     */
    /**
     * @param operator is the operator that wants to register as a DataLayr node
     * @param data is the meta-information that is required from operator for registering   
     */ 
    /**
     * @dev In order to minimize gas costs from storage, we adopted an approach where 
     *      we just store a hash of the all the ETH and Eigen staked by various DataLayr
     *      nodes into the chain and emit an event specifying the information on a new
     *      operator whenever it registers. Any operator wishing to register as a 
     *      DataLayr node has to gather all information on the existing DataLayr nodes
     *      and provide for it while regsitering itself with DataLayr.
     *
     *      The structure for @param data is given by:
     *        <uint8> <uint256> <bytes[(2)]> <uint256> <bytes[(2)]> <uint8> <bytes[(6)]>    
     *        < (1) > <  (2)  > <    (3)   > <  (4)  > <    (5)   > < (6) > <   (7)    >
     *
     *      where,
     *        (1) is registrantType that specifies whether the operator is an ETH validator,
     *            or Eigen validator or both,
     *        (2) is ethStakeLength which specifies length of (3),
     *        (3) is the list of the form [<(operator address, operator's ETH deposit)>, total ETH deposit],
     *            where <(operator address, operator's ETH deposit)> is the array of tuple
     *            (operator address, operator's ETH deposit) for operators who are DataLayr nodes,    
     *        (4) is eigenStakeLength which specifies length of (5),
     *        (5) is the list of the form [<(operator address, operator's Eigen deposit)>, total Eigen deposit],
     *            where <(operator address, operator's Eigen deposit)> is the array of tuple
     *            (operator address, operator's Eigen deposit) for operators who are DataLayr nodes,       
     *        (6) is socketLength which specifies length of (7),
     *        (7) is the socket 
     */ 
    function registerOperator(address operator, bytes calldata data)
        public
        returns (uint8, uint128)
    {
        require(
            registry[operator].active == 0,
            "Operator is already registered"
        );

        // get the first byte of data
        uint8 registrantType = data.toUint8(0);

        //length of socket in bytes
        uint256 socketLengthPointer = 33;
        uint128 eigenAmount;
        if (registrantType == 1) {
            // if they want to be an "eigen" validator, check that they meet the eigen requirements
            eigenAmount = weightOfOperatorEigen(operator);
            require(eigenAmount >= dlnEigenStake, "Not enough eigen staked");
            //parse and update eigen stakes
            uint256 eigenStakesLength = data.toUint256(1);
            //increment socket length pointer
            addOperatorToEigenStakes(
                data.slice(33, eigenStakesLength),
                operator,
                eigenAmount
            );
            socketLengthPointer += 33 + eigenStakesLength;
        } else if (registrantType == 2) {
            // if they want to be an "eth" validator, check that they meet the eth requirements
            uint128 ethAmount = weightOfOperatorEth(operator);
            require(ethAmount >= dlnEthStake, "Not enough eth value staked");
            //parse and update eth stakes
            uint256 ethStakesLength = data.toUint256(1);
            //increment socket length pointer
            
            addOperatorToEthStakes(
                // CRITIC: change from 32 to 33
                data.slice(32, ethStakesLength),
                operator,
                ethAmount
            );
            socketLengthPointer +=  32 + ethStakesLength;
        } else if (registrantType == 3) {
            // if they want to be an "eigen and eth" validator, check that they meet the eigen and eth requirements
            eigenAmount = weightOfOperatorEigen(operator);
            uint128 ethAmount = weightOfOperatorEth(operator);
            require(
                eigenAmount >= dlnEigenStake && ethAmount >= dlnEthStake,
                "Not enough eth value or eigen staked"
            );
            //parse and update eth and eigen stakes
            uint256 stakesLength = data.toUint256(1);
            //increment socket length pointer
            addOperatorToEthStakes(
                data.slice(32, stakesLength),
                operator,
                ethAmount
            );
            socketLengthPointer += 32 + stakesLength;
            //now do it for eigen stuff
            stakesLength = data.toUint256(socketLengthPointer);
            //increment socket length pointer
            addOperatorToEigenStakes(
                data.slice(socketLengthPointer + 32, stakesLength),
                operator,
                eigenAmount
            );
            socketLengthPointer += stakesLength + 32;
        } else {
            revert("Invalid registrant type");
        }
        //slice starting the byte after socket length
        registry[operator] = Registrant({
            id: nextRegistrantId,
            index: uint64(queryManager.numRegistrants()),
            active: registrantType,
            fromDumpNumber: IDataLayrServiceManager(
                address(queryManager.feeManager())
            ).dumpNumber(),
            to: 0,
            socket: string(
                data.slice(
                    socketLengthPointer + 1,
                    data.toUint8(socketLengthPointer)
                )
            )
        });

        registrantList.push(operator);
        nextRegistrantId++;
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
        emit DeregistrationCommit(msg.sender);
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

    function addOperatorToEthStakes(
        bytes memory stakes,
        address operator,
        uint128 newEth
    ) internal {
        //stakes must be preimage of last update's hash
        require(
            keccak256(stakes) ==
                ethStakeHashes[
                    ethStakeHashUpdates[ethStakeHashUpdates.length - 1]
                ],
            "Stakes are incorrect"
        );
        //get dump number from dlsm
        uint48 currDumpNumber = IDataLayrServiceManager(
            address(queryManager.feeManager())
        ).dumpNumber();
        ethStakeHashUpdates.push(currDumpNumber);
        //add them to beginning of stakes
        ethStakeHashes[currDumpNumber] = keccak256(
            abi.encodePacked(
                operator,
                newEth,
                stakes.slice(0, stakes.length - 32).concat(
                    abi.encodePacked(
                        stakes.toUint256(stakes.length - 32) + newEth
                    )
                )
            )
        );

        emit EthStakeAdded(operator, newEth);
    }

    function addOperatorToEigenStakes(
        bytes memory stakes,
        address operator,
        uint128 newEigen
    ) internal {
        //stakes must be preimage of last update's hash
        require(
            keccak256(stakes) ==
                eigenStakeHashes[
                    eigenStakeHashUpdates[eigenStakeHashUpdates.length - 1]
                ],
            "Stakes are incorrect"
        );
        //get dump number from dlsm
        uint48 currDumpNumber = IDataLayrServiceManager(
            address(queryManager.feeManager())
        ).dumpNumber();
        eigenStakeHashUpdates.push(currDumpNumber);
        //add them to beginning of stakes
        eigenStakeHashes[currDumpNumber] = keccak256(
            abi.encodePacked(
                operator,
                newEigen,
                stakes.slice(0, stakes.length - 32).concat(
                    abi.encodePacked(
                        stakes.toUint256(stakes.length - 32) + newEigen
                    )
                )
            )
        );

        emit EigenStakeAdded(operator, newEigen);
    }

    //stakes must be of the form
    //address,uint128,address,uint128...uint256
    function updateEthStakes(
        bytes memory stakes,
        address[] memory operators,
        uint32[] memory indexes
    ) public {
        //stakes must be preimage of last update's hash
        require(
            keccak256(stakes) ==
                ethStakeHashes[
                    ethStakeHashUpdates[ethStakeHashUpdates.length - 1]
                ],
            "Stakes are incorrect"
        );
        require(
            indexes.length == operators.length,
            "operator len and index len don't match"
        );
        uint256 len = operators.length;
        for (uint i = 0; i < len; ) {
            //36 bytes per person: 20 for address, 16 for stake
            uint256 start = uint256(indexes[i] * 36);
            require(start < stakes.length - 68, "Cannot point to total bytes");
            require(
                stakes.toAddress(start) == operators[i],
                "index is incorrect"
            );
            //find current stake and new stake
            Uint128xUint128 memory currentAndNewEth = Uint128xUint128({
                a: stakes.toUint128(start + 20),
                b: weightOfOperatorEth(operators[i])
            });
            //replace stake with new eth stake
            stakes = stakes
            .slice(0, start + 20)
            .concat(abi.encodePacked(currentAndNewEth.b))
            //from where left off to right before the last 32 bytes
            //68 = 36 + 32. we want to end slice just prior to last 32 bytes
            .concat(stakes.slice(start + 36, stakes.length - (start + 68)))
            //subtract old eth and add new eth
                .concat(
                    abi.encodePacked(
                        stakes.toUint256(stakes.length - 32) +
                            currentAndNewEth.a -
                            currentAndNewEth.b
                    )
                );
            unchecked {
                ++i;
            }
            emit EthStakeUpdate(operators[i], currentAndNewEth.b);
        }
        //get dump number from dlsm
        uint48 currDumpNumber = IDataLayrServiceManager(
            address(queryManager.feeManager())
        ).dumpNumber();
        ethStakeHashUpdates.push(currDumpNumber);
        ethStakeHashes[currDumpNumber] = keccak256(stakes);
    }

    //stakes must be of the form
    //address,uint128,address,uint128...uint256
    function updateEigenStakes(
        bytes memory stakes,
        address[] memory operators,
        uint32[] memory indexes
    ) public {
        //stakes must be preimage of last update's hash
        require(
            keccak256(stakes) ==
                eigenStakeHashes[
                    eigenStakeHashUpdates[eigenStakeHashUpdates.length - 1]
                ],
            "Stakes are incorrect"
        );
        require(
            indexes.length == operators.length,
            "operator len and index len don't match"
        );
        uint256 len = operators.length;
        for (uint i = 0; i < len; ) {
            uint128 newEigen = weightOfOperatorEigen(operators[i]);
            uint256 start = uint256(indexes[i] * 36);
            //last 32 bytes for total stake
            require(start < stakes.length - 68, "Cannot point to total bytes");
            //36 bytes per person: 20 for address, 16 for stake
            require(
                stakes.toAddress(start) == operators[i],
                "index is incorrect"
            );
            //replace stake with new eigen stake
            //68 = 36 + 32. we want to end slice just prior to last 32 bytes
            stakes = stakes
            .slice(0, start + 20)
            .concat(abi.encodePacked(uint256(newEigen)))
            .concat(stakes.slice(start + 36, stakes.length - (start + 68)))
            //subtract old eigen and add new eigen
                .concat(
                    abi.encodePacked(
                        stakes.toUint256(stakes.length - 32) -
                            stakes.toUint128(start + 20) +
                            newEigen
                    )
                );
            emit EigenStakeUpdate(operators[i], newEigen);
            unchecked {
                ++i;
            }
        }
        //get dump number from dlsm
        uint48 currDumpNumber = IDataLayrServiceManager(
            address(queryManager.feeManager())
        ).dumpNumber();
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

    function setDlnEigenStake(uint128 _dlnEigenStake) public onlyQMGovernance {
        dlnEigenStake = _dlnEigenStake;
    }

    function setDlnEthStake(uint128 _dlnEthStake) public onlyQMGovernance {
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

    function getEthStakesHashUpdate(uint256 index)
        public
        view
        returns (uint256)
    {
        return ethStakeHashUpdates[index];
    }

    function getEigenStakesHashUpdate(uint256 index)
        public
        view
        returns (uint256)
    {
        return eigenStakeHashUpdates[index];
    }

    function getEthStakesHashUpdateAndCheckIndex(
        uint256 index,
        uint48 dumpNumber
    ) public view returns (bytes32) {
        uint48 dumpNumberAtIndex = ethStakeHashUpdates[index];
        require(
            dumpNumberAtIndex <= dumpNumber,
            "DumpNumber at index is not less than or equal dumpNumber"
        );
        if (index != ethStakeHashUpdates.length - 1) {
            require(
                ethStakeHashUpdates[index + 1] > dumpNumber,
                "DumpNumber at index is not less than or equal dumpNumber"
            );
        }
        return ethStakeHashes[dumpNumberAtIndex];
    }

    function getEigenStakesHashUpdateAndCheckIndex(
        uint256 index,
        uint48 dumpNumber
    ) public view returns (bytes32) {
        uint48 dumpNumberAtIndex = eigenStakeHashUpdates[index];
        require(
            dumpNumberAtIndex <= dumpNumber,
            "DumpNumber at index is not less than or equal dumpNumber"
        );
        if (index != eigenStakeHashUpdates.length - 1) {
            require(
                eigenStakeHashUpdates[index + 1] > dumpNumber,
                "DumpNumber at index is not less than or equal dumpNumber"
            );
        }
        return eigenStakeHashes[dumpNumberAtIndex];
    }

    function getEthStakesHashUpdateLength() public view returns (uint256) {
        return ethStakeHashUpdates.length;
    }

    function getEigenStakesHashUpdateLength() public view returns (uint256) {
        return eigenStakeHashUpdates.length;
    }
}
