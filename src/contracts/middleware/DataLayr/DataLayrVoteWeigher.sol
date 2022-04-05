// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IQueryManager.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IDataLayrServiceManager.sol";
import "../../interfaces/IInvestmentManager.sol";
import "../../libraries/BytesLib.sol";
import "../QueryManager.sol";
import "ds-test/test.sol";

/**
 * @notice
 */

contract DataLayrVoteWeigher is IVoteWeighter, IRegistrationManager, DSTest {
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

    /**
     * @notice pack two uint128's into a storage slot
     */
    struct Uint48xUint48 {
        uint48 a;
        uint48 b;
    }

    // EVENT
    /**
     * @notice
     */
    event Registration();

    event DeregistrationCommit(
        address registrant // who started
    );

    event EthStakeAdded(
        address operator,
        uint128 stake,
        uint48 dumpNumber,
        uint48 prevUpdateDumpNumber
    );
    event EigenStakeAdded(
        address operator,
        uint128 stake,
        uint48 dumpNumber,
        uint48 prevUpdateDumpNumber
    );
    event EthStakeUpdate(
        address operator,
        uint128 stake,
        uint48 dumpNumber,
        uint48 prevUpdateDumpNumber
    );
    event EigenStakeUpdate(
        address operator,
        uint128 stake,
        uint48 dumpNumber,
        uint48 prevUpdateDumpNumber
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

        //TODO: make sure this works!
        //initialize the ETH and EIGEN stakes
        eigenStakeHashUpdates.push(0);
        ethStakeHashUpdates.push(0);
        //bytes memory zero = "0x00000000000000000000000000000000";
        //bytes32 zeroHash = keccak256(zero);
        bytes32 zeroHash = keccak256(abi.encode(bytes32(0)));
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
     *      DataLayr node has to gather information on the existing DataLayr nodes
     *      of its type and provide for it while registering itself with DataLayr.
     *
     *      The structure for @param data is given by:
     *        <uint8> <uint256> <bytes[(2)]> <uint256> <bytes[(5)]> <uint8> <bytes[(6)]>    
     *        < (1) > <  (2)  > <    (3)   > <  (4)  > <    (5)   > < (6) > <   (7)    >
     *
     *      where,
     *        (1) is registrantType that specifies whether the operator is an ETH DataLayr node,
     *            or Eigen DataLayr node or both,
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
     *
     *      An important point to note is that if the operator is registering itself as
     *      ETH DataLayr node, it shouldn't provide info on Eigen DataLayr nodes or the length. Vice versa if the operator is registering itself as 
     *      Eigen DataLayr nodes. However, if the operator is registering itself as 
     *      an ETH-Eigen DataLayr node, then it needs to give information on both types
     *      existing DataLayr nodes. 
     *
     */ 
    function registerOperator(address operator, bytes calldata data)
        public
        returns (uint8, uint128)
    {
        require(
            registry[operator].active == 0,
            "Operator is already registered"
        );

        // get the first byte of data which happens to specify the type of the operator
        uint8 registrantType = data.toUint8(0);

        // pointer to where socketLength is stored
        /**
         * @dev increment by 1 for storing registrantType which has already been obtained
         */
        uint256 socketLengthPointer = 1;

        // CRITIC: do we need to declare it?
        uint128 eigenAmount;

        if (registrantType == 1) {
            // if operator want to be an "Eigen" validator, check that they meet the 
            // minimum requirements on how much Eigen it must deposit
            eigenAmount = weightOfOperatorEigen(operator);
            require(eigenAmount >= dlnEigenStake, "Not enough eigen staked");

            // parse the length 
            /// @dev this is (4) in the description just before the current function 
            uint256 eigenStakesLength = data.toUint256(1);

            // add the tuple (operator address, operator's stake) to the meta-information
            // on the Eigen stakes of the existing DataLayr nodes
            addOperatorToEigenStakes(
                data.slice(socketLengthPointer + 32, eigenStakesLength),
                operator,
                eigenAmount
            );

            /**
             * @dev increment by 32 for storing uint256 eigenStakesLength and 
             *      eigenStakesLength for storing the actual meta-data on Eigen staked 
             *      by each existing DataLayr nodes, 
             */
            socketLengthPointer += (32 + eigenStakesLength);

        } else if (registrantType == 2) {
            // if operator want to be an "ETH" validator, check that they meet the 
            // minimum requirements on how much ETH it must deposit
            uint128 ethAmount = weightOfOperatorEth(operator);
            require(ethAmount >= dlnEthStake, "Not enough eth value staked");

            // parse the length 
            /// @dev this is (2) in the description just before the current function 
            uint256 ethStakesLength = data.toUint256(1);
            

            // add the tuple (operator address, operator's stake) to the meta-information
            // on the ETH stakes of the existing DataLayr nodes
            addOperatorToEthStakes(
                data.slice(socketLengthPointer + 32, ethStakesLength),
                operator,
                ethAmount
            );

            /**
             * @dev increment by 32 for storing uint256 ethStakesLength and 
             *      ethStakesLength for storing the actual meta-data on ETH staked 
             *      by each existing DataLayr nodes.
             */
            socketLengthPointer += (32 + ethStakesLength);

        } else if (registrantType == 3) {
            // if they want to be an "eigen and eth" validator, check that they meet 
            // the Eigen and ETH requirements
            eigenAmount = weightOfOperatorEigen(operator);
            uint128 ethAmount = weightOfOperatorEth(operator);
            require(
                eigenAmount >= dlnEigenStake && ethAmount >= dlnEthStake,
                "Not enough eth value or eigen staked"
            );

            // parse the length
            uint256 stakesLength = data.toUint256(1);

            // add the tuple (operator address, operator's stake) to the meta-information
            // on the ETH stakes of the existing DataLayr nodes
            addOperatorToEthStakes(
                data.slice(socketLengthPointer + 32, stakesLength),
                operator,
                ethAmount
            );

            // increment the pointer
            socketLengthPointer += (32 + stakesLength);

            // parse the length
            stakesLength = data.toUint256(socketLengthPointer);

            // increment socket length pointer
            addOperatorToEigenStakes(
                data.slice(socketLengthPointer + 32, stakesLength),
                operator,
                eigenAmount
            );

            // increment the pointer
            socketLengthPointer += (32 + stakesLength);
        } else {
            revert("Invalid registrant type");
        }

        // slice starting the byte after socket length to construct the details on the 
        // DataLayr node
        registry[operator] = Registrant({
            id: nextRegistrantId,
            index: uint64(queryManager.numRegistrants()),
            active: registrantType,
            fromDumpNumber: IDataLayrServiceManager(
                address(queryManager.feeManager())
            ).dumpNumber(),
            to: 0,

            // extract the socket address 
            socket: string(
                data.slice(
                    socketLengthPointer + 1,
                    data.toUint8(socketLengthPointer)
                )
            )
        });

        // record the operator being registered
        registrantList.push(operator);

        // update the counter for registrant ID
        nextRegistrantId++;

        return (registrantType, eigenAmount);

        // CRITIC: there should be event here?
    }

    /**
     * @notice Used for notifying that operator wants to deregister from being 
     *         a DataLayr node 
     */
    function commitDeregistration() public returns (bool) {
        require(
            registry[msg.sender].active > 0,
            "Operator is already registered"
        );
        
        // they must store till the latest time a dump expires
        registry[msg.sender].to = latestTime;

        // committing to not signing off on any more data that is being asserted into DataLayr
        registry[msg.sender].active = 0;

        emit DeregistrationCommit(msg.sender);
        return true;
    }


    /**
     * @notice 
     */
    // CRITIC: what is this calldata variable for?
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


    /**
     * @notice Used for appending the ETH stakes of an operator that has registered 
     *         as a new DataLayr node 
     */
    /**
     * @param stakes is the meta-data on the existing DataLayr nodes' addresses and 
     *        their ETH deposits. This is in abi-encoded form of the list of 
     *        the form: 
     *          (dln1's addr, dln1's ETH deposit), (dln2's addr, dln2's ETH deposit), ...
     * @param operator is the address who is registering  as a new DataLayr node.
     * @param newEth is the amount of ETH that the operator has deposited in EigenLAyr. 
     */
    function addOperatorToEthStakes(
        bytes memory stakes,
        address operator,
        uint128 newEth
    ) internal {
        // stakes must be preimage of last update's hash
        require(
            keccak256(stakes) ==
                ethStakeHashes[
                    ethStakeHashUpdates[ethStakeHashUpdates.length - 1]
                ],
            "Stakes are incorrect"
        );

        // get current dump number from DataLayrServiceManagerStorage.sol
        uint48 currDumpNumber = IDataLayrServiceManager(
            address(queryManager.feeManager())
        ).dumpNumber();

        ethStakeHashUpdates.push(currDumpNumber);

        // store the updated meta-data in the mapping with the key being the current dump number
        /** 
         * @dev append the tuple (operator's address, operator's ETH deposit in EigenLayr)
         *      at the front of the list of tuples pertaining to existing DataLayr nodes. 
         *      Also, need to update the total ETH deposited by all DataLayr nodes.
         */
        ethStakeHashes[currDumpNumber] = keccak256(
            abi.encodePacked(
                // append at the front
                operator,
                newEth,
                stakes.slice(0, stakes.length - 32).concat(
                    abi.encodePacked(
                        // update the total ETH deposited
                        stakes.toUint256(stakes.length - 32) + newEth
                    )
                )
            )
        );

        emit EthStakeAdded(
            operator,
            newEth,
            currDumpNumber,
            ethStakeHashUpdates[ethStakeHashUpdates.length - 1]
        );
    }


    /**
     * @notice Used for appending the Eigen stakes of an operator that has registered 
     *         as a new DataLayr node 
     */
    /**
     * @param stakes is the meta-data on the existing DataLayr nodes' addresses and 
     *        their Eigen deposits. This is in abi-encoded form of the list of 
     *        the form 
     *          (dln1's addr, dln1's Eigen deposit), (dln2's addr, dln2's Eigen deposit), ...
     * @param operator is the address who is registering  as a new DataLayr node.
     * @param newEigen is the amount of Eigen that the operator has deposited in EigenLAyr. 
     */
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

        // get current dump number from DataLayrServiceManagerStorage.sol
        uint48 currDumpNumber = IDataLayrServiceManager(
            address(queryManager.feeManager())
        ).dumpNumber();

        eigenStakeHashUpdates.push(currDumpNumber);
        
        // store the updated meta-data in the mapping with the key being the current dump number
        /** 
         * @dev append the tuple (operator's address, operator's Eigen deposit in EigenLayr)
         *      at the front of the list of tuples pertaining to existing DataLayr nodes. 
         *      Also, need to update the total Eigen deposited by all DataLayr nodes.
         */
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

        emit EigenStakeAdded(
            operator,
            newEigen,
            currDumpNumber,
            ethStakeHashUpdates[ethStakeHashUpdates.length - 1]
        );
    }



    /**
     * @notice Used for updating information on ETH deposits of DataLayr nodes. 
     */
    /**
     * @param stakes is the meta-data on the existing DataLayr nodes' addresses and 
     *        their ETH deposits. This param is in abi-encoded form of the list of 
     *        the form 
     *          (dln1's addr, dln1's ETH deposit), (dln2's addr, dln2's ETH deposit), ...
     * @param operators are the DataLayr nodes whose information on their ETH deposits
     *        getting updated
     * @param indexes are the tuple positions whose corresponding ETH deposit is 
     *        getting updated  
     */ 
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

        // get dump number from DataLayrServiceManagerStorage.sol
        Uint48xUint48 memory dumpNumbers = Uint48xUint48(
            IDataLayrServiceManager(address(queryManager.feeManager()))
                .dumpNumber(),
            ethStakeHashUpdates[ethStakeHashUpdates.length - 1]
        );

        // iterating over all the tuples that is to be updated
        for (uint i = 0; i < operators.length; ) {

            // placing the pointer at the starting byte of the tuple 
            /// @dev 36 bytes per DataLayr node: 20 bytes for address, 16 bytes for its ETH deposit
            uint256 start = uint256(indexes[i] * 36);

            require(start < stakes.length - 68, "Cannot point to total bytes");

            require(
                stakes.toAddress(start) == operators[i],
                "index is incorrect"
            );

            // determine current stake and new stake
            Uint128xUint128 memory currentAndNewEth = Uint128xUint128({
                a: stakes.toUint128(start + 20),
                b: weightOfOperatorEth(operators[i])
            });

            // replacing ETH deposit of the operator with updated ETH deposit
            stakes = stakes
            // slice until the address bytes of the DataLayr node
            .slice(0, start + 20)
            // concatenate the updated ETH deposit
            .concat(abi.encodePacked(currentAndNewEth.b))
            // concatenate the bytes pertaining to the tuples from rest of the DataLayr 
            // nodes except the last 32 bytes that comprises of total ETH deposits
            .concat(stakes.slice(start + 36, stakes.length - (start + 68)))
            // concatenate the updated ETH deposit in the last 32 bytes,
            // subtract old ETH deposit and add the updated ETH deposit
                .concat(
                    abi.encodePacked(
                        stakes.toUint256(stakes.length - 32) +
                            currentAndNewEth.a -
                            currentAndNewEth.b
                    )
                );
            emit EthStakeUpdate(
                operators[i],
                currentAndNewEth.b,
                dumpNumbers.a,
                dumpNumbers.b
            );
            unchecked {
                ++i;
            }
        }
        ethStakeHashUpdates.push(dumpNumbers.a);

        // record the commitment
        ethStakeHashes[dumpNumbers.a] = keccak256(stakes);
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
        //get dump number from dlsm
        //get dump number from dlsm
        Uint48xUint48 memory dumpNumbers = Uint48xUint48(
            IDataLayrServiceManager(address(queryManager.feeManager()))
                .dumpNumber(),
            ethStakeHashUpdates[ethStakeHashUpdates.length - 1]
        );
        for (uint i = 0; i < operators.length; ) {
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
            emit EigenStakeUpdate(
                operators[i],
                newEigen,
                dumpNumbers.a,
                dumpNumbers.b
            );
            unchecked {
                ++i;
            }
        }
        eigenStakeHashUpdates.push(dumpNumbers.a);
        eigenStakeHashes[dumpNumbers.a] = keccak256(stakes);
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
