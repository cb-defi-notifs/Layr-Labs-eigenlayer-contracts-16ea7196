// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrServiceManager.sol";
import "../../libraries/BytesLib.sol";
import "../Repository.sol";
import "../VoteWeigherBase.sol";
import "ds-test/test.sol";

/**
 * @notice
 */

contract DataLayrVoteWeigher is VoteWeigherBase, IRegistrationManager, DSTest {
    using BytesLib for bytes;
    /**
     * @notice  Details on DataLayr nodes that would be used for -
     *           - sending data by the sequencer
     *           - querying by any challenger/retriever
     *           - payment and associated challenges
     */
    struct Registrant {
        // id is always unique
        uint32 id;
        // corresponds to position in registrantList
        uint64 index;
        //
        uint48 fromDumpNumber;
        uint32 to;
        uint8 active; //bool
        // socket address of the DataLayr node
        string socket;
    }

    /**
     * @notice struct for storing the amount of Eigen and ETH that has been staked, as well as additional data
     *          packs two uint96's into a single storage slot
     */
    struct EthAndEigenAmounts {
        uint96 ethAmount;
        uint96 eigenAmount;
    }
    
    /**
     * @notice pack two uint48's into a storage slot
     */
    struct Uint48xUint48 {
        uint48 a;
        uint48 b;
    }

//BEGIN ADDED FUNCTIONALITY FOR STORING STAKES AND REGISTRATION
// TODO: de-duplicate this struct and the EthAndEigenAmounts struct
    // struct for storing the amount of Eigen and ETH that has been staked, as well as additional data

    // variable for storing total ETH and Eigen staked into securing the middleware
    EthAndEigenAmounts public totalStake;

    // mapping from each operator's address to its Stake for the middleware
    mapping(address => EthAndEigenAmounts) public operatorStakes;

    //TODO: do we need this variable?
    // number of registrants of this service
    uint64 public numRegistrants;

    /// @notice get total ETH staked for securing the middleware
    function totalEthStaked() public view returns (uint96) {
        return totalStake.ethAmount;
    }

    /// @notice get total Eigen staked for securing the middleware
    function totalEigenStaked() public view returns (uint96) {
        return totalStake.eigenAmount;
    }

    /// @notice get total ETH staked by delegators of the operator
    function ethStakedByOperator(address operator)
        public
        view
        returns (uint96)
    {
        return operatorStakes[operator].ethAmount;
    }

    /// @notice get total Eigen staked by delegators of the operator
    function eigenStakedByOperator(address operator)
        public
        view
        returns (uint96)
    {
        return operatorStakes[operator].eigenAmount;
    }

    /// @notice get both total ETH and Eigen staked by delegators of the operator
    function ethAndEigenStakedForOperator(address operator)
        public
        view
        returns (uint96, uint96)
    {
        EthAndEigenAmounts memory opStake = operatorStakes[operator];
        return (opStake.ethAmount, opStake.eigenAmount);
    }

    /// @notice returns the type for the specified operator
    function getOperatorType(address operator)
        public
        view
        returns (uint8)
    {
        return registry[operator].active;
    }
//END ADDED FUNCTIONALITY FOR STORING STAKES AND REGISTRATION

    // the latest UTC timestamp at which a DataStore expires
    uint32 public latestTime;

    uint32 public nextRegistrantId;
    uint128 public dlnEthStake = 1 wei;
    uint128 public dlnEigenStake = 1 wei;

    // Register, everyone is active in the list
    mapping(address => Registrant) public registry;
    //mapping from dumpNumbers to hash of the 'stake' object at the dumpNumber
    mapping(uint48 => bytes32) public stakeHashes;
    //dumpNumbers at which the stake object was updated
    uint48[] public stakeHashUpdates;
    address[] public registrantList;

    // EVENT
    /**
     * @notice
     */
    event Registration();

    event DeregistrationCommit(
        address registrant // who started
    );

    event StakeAdded( 
        address operator,
        uint96 ethStake, 
        uint96 eigenStake,         
        uint256 updateNumber,
        uint48 dumpNumber,
        uint48 prevDumpNumber
    );
    // uint48 prevUpdateDumpNumber 

    event StakeUpdate(
        address operator,
        uint96 ethStake,
        uint96 eigenStake,
        uint48 dumpNumber,
        uint48 prevUpdateDumpNumber
    );
    event EigenStakeUpdate(
        address operator,
        uint128 stake,
        uint48 dumpNumber,
        uint48 prevUpdateDumpNumber
    );

    modifier onlyRepositoryGovernance() {
        require(
            address(repository.timelock()) == msg.sender,
            "only repository governance can call this function"
        );
        _;
    }

    modifier onlyRepository() {
        require(address(repository) == msg.sender, "onlyRepository");
        _;
    }

    constructor(
        IEigenLayrDelegation _delegation,
        uint256 _consensusLayerEthToEth
    ) VoteWeigherBase(_delegation, _consensusLayerEthToEth) {
        //initialize the stake object
        stakeHashUpdates.push(0);
        //input is length 24 zero bytes (12 bytes each for ETH & EIGEN totals, which both start at 0)
        bytes32 zeroHash = keccak256(abi.encodePacked(bytes24(0)));
        //initialize the mapping
        stakeHashes[0] = zeroHash;
    }

    /**
     * @notice returns the total Eigen delegated by delegators with this operator
     */
    /**
     * @dev minimum delegation limit has to be satisfied.
     */
    function weightOfOperatorEigen(address operator)
        public override
        view
        returns (uint128)
    {
        uint128 eigenAmount = super.weightOfOperatorEigen(operator);

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
    function weightOfOperatorEth(address operator) public override returns (uint128) {
        uint128 amount = super.weightOfOperatorEth(operator);

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
     *      and provide it while registering itself with DataLayr.
     *
     *      The structure for @param data is given by:
     *        <uint8> <uint256> <bytes[(2)]> <uint8> <bytes[(4)]>    
     *        < (1) > <  (2)  > <    (3)   > < (4) > <   (5)    >
     *
     *      where,
     *        (1) is registrantType that specifies whether the operator is an ETH DataLayr node,
     *            or Eigen DataLayr node or both,
     *        (2) is stakeLength which specifies length of (3),
     *        (3) is the list of the form [<(operator address, operator's ETH deposit, operator's EIGEN deposit)>,
     *                                      total ETH deposit, total EIGEN deposit],
     *            where <(operator address, operator's ETH deposit, operator's EIGEN deposit)> is the array of tuple
     *            (operator address, operator's ETH deposit, operator's EIGEN deposit) for operators who are DataLayr nodes, 
     * 
     *              
     *        (4) is socketLength which specifies length of (7),
     *        (5) is the socket 
     *
     *      An important point to note that each operator's ETH deposit (EIGEN deposit) is left out of the member of the tuple in the event that the
     *              operator has registrantType with first (second) bit 0.
     *      When registering as a node, a new node operator must provide the existing stake information (since we only store the hash, rather than
     *      storing the entire object in storage)
     *
     */ 
// TODO: decide if address input is necessary for the standard
    function registerOperator(address, bytes calldata data)
        external
        returns (uint8, uint96, uint96)
    {
        // address operator = msg.sender;
        require(
            registry[msg.sender].active == 0,
            "Operator is already registered"
        );

        // get the first byte of data which happens to specify the type of the operator
        uint8 registrantType = data.toUint8(0);

        // TODO: shared struct type for this + registrantType, also used in Repository?
        EthAndEigenAmounts memory ethAndEigenAmounts;

        //if first bit of registrantType is '1', then operator wants to be an ETH validator
        if ((registrantType & 0x00000001) == 0x00000001) {
            // if operator want to be an "ETH" validator, check that they meet the 
            // minimum requirements on how much ETH it must deposit
            ethAndEigenAmounts.ethAmount = uint96(weightOfOperatorEth(msg.sender));
            require(ethAndEigenAmounts.ethAmount >= dlnEthStake, "Not enough eth value staked");
        }

        //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
        if ((registrantType & 0x00000002) == 0x00000002) {
            // if operator want to be an "Eigen" validator, check that they meet the 
            // minimum requirements on how much Eigen it must deposit
            ethAndEigenAmounts.eigenAmount = uint96(weightOfOperatorEigen(msg.sender));
            require(ethAndEigenAmounts.eigenAmount >= dlnEigenStake, "Not enough eigen staked");
        }

        //bytes to add to the existing stakes object
        bytes memory dataToAppend = abi.encodePacked(msg.sender, ethAndEigenAmounts.ethAmount, ethAndEigenAmounts.eigenAmount);

        require(ethAndEigenAmounts.ethAmount > 0 || ethAndEigenAmounts.eigenAmount > 0, "must register as at least one type of validator");
        // parse the length 
        /// @dev this is (2) in the description just before the current function 
        uint256 stakesLength = data.toUint256(1);

        // add the tuple (operator address, operator's stake) to the meta-information
        // on the stakes of the existing DataLayr nodes
        // '33' is used here to account for registrantType (already read) and stakesLength
        bytes memory stakes = data.slice(33, stakesLength);

        // stakes must be preimage of last update's hash
        // uint48 prevDumpNumber = stakeHashUpdates[stakeHashUpdates.length - 1];
        // bytes32 prevHash = stakeHashes[stakeHashUpdates[stakeHashUpdates.length - 1]];

        require(
            keccak256(stakes) == stakeHashes[stakeHashUpdates[stakeHashUpdates.length - 1]],
            "Supplied stakes are incorrect"
        );


        // slice starting the byte after socket length to construct the details on the 
        // DataLayr node
        registry[msg.sender] = Registrant({
            id: nextRegistrantId,
            index: numRegistrants,
            active: registrantType,
            fromDumpNumber: IDataLayrServiceManager(
                address(repository.ServiceManager())
            ).dumpNumber(),
            to: 0,

            // extract the socket address 
            socket: string(
                data.slice(
                    //begin just after byte where socket length is specified
                    (34 + stakesLength),
                    //fetch byte that specifies socket length
                    data.toUint8(33 + stakesLength)
                )
            )
        });

        // record the operator being registered
        registrantList.push(msg.sender);

        // update the counter for registrant ID
        unchecked {
            ++nextRegistrantId;
        }

        // get current dump number from DataLayrServiceManager
        uint48 currentDumpNumber = IDataLayrServiceManager(
            address(repository.ServiceManager())
        ).dumpNumber();

        // TODO: Optimize storage calls
        emit StakeAdded(msg.sender, ethAndEigenAmounts.ethAmount, ethAndEigenAmounts.eigenAmount, stakeHashUpdates.length, currentDumpNumber, stakeHashUpdates[stakeHashUpdates.length - 1]);


        // store the updated meta-data in the mapping with the key being the current dump number
        /** 
         * @dev append the tuple (operator's address, operator's ETH deposit in EigenLayr)
         *      at the front of the list of tuples pertaining to existing DataLayr nodes. 
         *      Also, need to update the total ETH and/or EIGEN deposited by all DataLayr nodes.
         */
        stakeHashes[currentDumpNumber] = keccak256(
            abi.encodePacked(
                stakes.slice(0, stakes.length - 24),
                // append at the end of list
                dataToAppend,
                // update the total ETH deposited
                stakes.toUint96(stakes.length - 24) + ethAndEigenAmounts.ethAmount,
                // update the total EIGEN deposited
                stakes.toUint96(stakes.length - 12) + ethAndEigenAmounts.eigenAmount
            )
        );

        stakeHashUpdates.push(currentDumpNumber);

        //update stakes in storage
        operatorStakes[msg.sender] = ethAndEigenAmounts;

        /**
         * update total Eigen and ETH that are being employed by the operator for securing
         * the queries from middleware via EigenLayr
         */
        //i think this gets batched as 1 SSTORE @TODO check
        totalStake.ethAmount += ethAndEigenAmounts.ethAmount;
        totalStake.eigenAmount += ethAndEigenAmounts.eigenAmount;

        //TODO: do we need this variable at all?
        //increment number of registrants
        unchecked {
            ++numRegistrants;
        }

        // TODO: do we need this return data?
        return (registrantType, ethAndEigenAmounts.ethAmount, ethAndEigenAmounts.eigenAmount);
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
     * @notice Used by an operator to de-register itself from providing service to the middleware.
     */
// TODO: decide if address input is necessary for the standard
    function deregisterOperator(address, bytes calldata)
        external
        returns (bool)
    {
        address operator = msg.sender;
        // TODO: verify this check is adequate
        require(
            registry[operator].to != 0 ||
                registry[operator].to < block.timestamp,
            "Operator is already registered"
        );

        // subtract the staked Eigen and ETH of the operator that is getting deregistered
        // from the total stake securing the middleware
        totalStake.ethAmount -= operatorStakes[operator].ethAmount;
        totalStake.eigenAmount -= operatorStakes[operator].eigenAmount;

        // clear the staked Eigen and ETH of the operator which is getting deregistered
        operatorStakes[operator].ethAmount = 0;
        operatorStakes[operator].eigenAmount = 0;

        //decrement number of registrants
        unchecked {
            --numRegistrants;
        }

        return true;
    }

    /**
     * @notice Used for updating information on ETH and EIGEN deposits of DataLayr nodes. 
     */
    /**
     * @param stakes is the meta-data on the existing DataLayr nodes' addresses and 
     *        their ETH and EIGEN deposits. This param is in abi-encodedPacked form of the list of 
     *        the form 
     *          (dln1's registrantType, dln1's addr, dln1's ETH deposit, dln1's EIGEN deposit),
     *          (dln2's registrantType, dln2's addr, dln2's ETH deposit, dln2's EIGEN deposit), ...
     *          (sum of all nodes' ETH deposits, sum of all nodes' EIGEN deposits)
     *          where registrantType is a uint8 and all others are a uint96
     * @param operators are the DataLayr nodes whose information on their ETH and EIGEN deposits
     *        getting updated
     * @param indexes are the tuple positions whose corresponding ETH and EIGEN deposit is 
     *        getting updated  
     */ 
    function updateStakes(
        bytes memory stakes,
        address[] memory operators,
        uint32[] memory indexes
    ) public {
        //provided 'stakes' must be preimage of last update's hash
        require(
            keccak256(stakes) ==
                stakeHashes[
                    stakeHashUpdates[stakeHashUpdates.length - 1]
                ],
            "Stakes are incorrect"
        );

        require(
            indexes.length == operators.length,
            "operator len and index len don't match"
        );

        // get dump number from DataLayrServiceManagerStorage.sol
        Uint48xUint48 memory dumpNumbers = Uint48xUint48(
            IDataLayrServiceManager(address(repository.ServiceManager()))
                .dumpNumber(),
            stakeHashUpdates[stakeHashUpdates.length - 1]
        );

        // iterating over all the tuples that are to be updated
        for (uint256 i = 0; i < operators.length; ) {

            // placing the pointer at the starting byte of the tuple 
            /// @dev 44 bytes per DataLayr node: 20 bytes for address, 12 bytes for its ETH deposit, 12 bytes for its EIGEN deposit
            uint256 start = uint256(indexes[i] * 44);

            require(start < stakes.length - 68, "Cannot point to total bytes");

            require(
                stakes.toAddress(start) == operators[i],
                "index is incorrect"
            );

            // determine current stakes
            EthAndEigenAmounts memory currentStakes = EthAndEigenAmounts({
                ethAmount: stakes.toUint96(start + 20),
                eigenAmount: stakes.toUint96(start + 32)
            });

            // determine new stakes
            EthAndEigenAmounts memory newStakes = EthAndEigenAmounts({
                ethAmount: uint96(weightOfOperatorEth(operators[i])),
                eigenAmount: uint96(weightOfOperatorEigen(operators[i]))
            });

            // check if minimum requirements have been met
            if (newStakes.ethAmount < dlnEthStake) {
                newStakes.ethAmount = uint96(0);
            }
            if (newStakes.eigenAmount < dlnEigenStake) {
                newStakes.eigenAmount = uint96(0);
            }

            // find new stakes object, replacing deposit of the operator with updated deposit
            stakes = stakes
            // slice until just after the address bytes of the DataLayr node
            .slice(0, start + 20)
            // concatenate the updated ETH and EIGEN deposits
            .concat(abi.encodePacked(newStakes.ethAmount, newStakes.eigenAmount));
//TODO: updating 'stake' was split into two actions to solve 'stack too deep' error -- but it should be possible to fix this
            stakes = stakes
            // concatenate the bytes pertaining to the tuples from rest of the DataLayr 
            // nodes except the last 24 bytes that comprises of total ETH deposits
            .concat(stakes.slice(start + 44, stakes.length - (start + 68))) //68 = 44 + 24
            // concatenate the updated deposits in the last 24 bytes,
            // subtract old ETH and EIGEN deposits and add the updated deposits
                .concat(
                    abi.encodePacked(
                        (stakes.toUint96(stakes.length - 24) + newStakes.ethAmount - currentStakes.ethAmount),
                        (stakes.toUint96(stakes.length - 12) + newStakes.eigenAmount - currentStakes.eigenAmount)
                    )
                );
            // push new stake to storage
            operatorStakes[operators[i]] = newStakes;
            // update the total stake
            totalStake.ethAmount = totalStake.ethAmount + newStakes.ethAmount - currentStakes.ethAmount;
            totalStake.eigenAmount = totalStake.eigenAmount + newStakes.eigenAmount - currentStakes.eigenAmount;
            emit StakeUpdate(
                operators[i],
                newStakes.ethAmount,
                newStakes.eigenAmount,
                dumpNumbers.a,
                dumpNumbers.b
            );
            unchecked {
                ++i;
            }
        }
        stakeHashUpdates.push(dumpNumbers.a);

        // record the commitment
        stakeHashes[dumpNumbers.a] = keccak256(stakes);
    }

    function getOperatorFromDumpNumber(address operator)
        public
        view
        returns (uint48)
    {
        return registry[operator].fromDumpNumber;
    }

    function setDlnEigenStake(uint128 _dlnEigenStake) public onlyRepositoryGovernance {
        dlnEigenStake = _dlnEigenStake;
    }

    function setDlnEthStake(uint128 _dlnEthStake) public onlyRepositoryGovernance {
        dlnEthStake = _dlnEthStake;
    }

    function setLatestTime(uint32 _latestTime) public {
        require(
            address(repository.ServiceManager()) == msg.sender,
            "service manager can only call this"
        ); if (_latestTime > latestTime) {
            latestTime = _latestTime;            
        }
    }

    function getOperatorId(address operator) public view returns (uint32) {
        return registry[operator].id;
    }

    function getStakesHashUpdate(uint256 index)
        public
        view
        returns (uint256)
    {
        return stakeHashUpdates[index];
    }

    function getStakesHashUpdateAndCheckIndex(
        uint256 index,
        uint48 dumpNumber
    ) public view returns (bytes32) {
        uint48 dumpNumberAtIndex = stakeHashUpdates[index];
        require(
            dumpNumberAtIndex <= dumpNumber,
            "DumpNumber at index is not less than or equal dumpNumber"
        );
        if (index != stakeHashUpdates.length - 1) {
            require(
                stakeHashUpdates[index + 1] > dumpNumber,
                "!(stakeHashUpdates[index + 1] > dumpNumber)"
            );
        }
        return stakeHashes[dumpNumberAtIndex];
    }

    function getStakesHashUpdateLength() public view returns (uint256) {
        return stakeHashUpdates.length;
    }
}