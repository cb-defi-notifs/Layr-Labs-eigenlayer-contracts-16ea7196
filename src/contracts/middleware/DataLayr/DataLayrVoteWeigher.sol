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

    /**
     * @notice pack two uint96's into a storage slot
     */
    struct Uint96xUint96 {
        uint96 a;
        uint96 b;
    }

    /**
     * @notice pack two uint48's into a storage slot
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

    event StakeAdded(
        address operator,
        uint96 ethStake,
        uint96 eigenStake,
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

    //mapping from dumpNumbers to hash of the 'stake' object at the dumpNumber
    mapping(uint48 => bytes32) public stakeHashes;
    //dumpNumbers at which the stake object was updated
    uint48[] public stakeHashUpdates;

    constructor(
        IInvestmentManager _investmentManager,
        IEigenLayrDelegation _delegation
    ) {
        investmentManager = _investmentManager;
        delegation = _delegation;

        //initialize the stake object
        stakeHashUpdates.push(0);
        //input is length 24 zero bytes (12 bytes each for ETH & EIGEN totals, which both start at 0)
        bytes32 zeroHash = keccak256(abi.encodePacked(bytes24(0)));
        //initialize the mapping
        stakeHashes[0] = zeroHash;
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

        Uint96xUint96 memory ethAndEigenAmounts;
        // get current dump number from DataLayrServiceManagerStorage.sol
        uint48 currDumpNumber = IDataLayrServiceManager(
            address(queryManager.feeManager())
        ).dumpNumber();


        //if first bit of registrantType is '1', then operator wants to be an ETH validator
        if ((registrantType & 0x00000001) == 0x00000001) {
            // if operator want to be an "ETH" validator, check that they meet the 
            // minimum requirements on how much ETH it must deposit
            ethAndEigenAmounts.a = uint96(weightOfOperatorEth(operator));
            require(ethAndEigenAmounts.a >= dlnEthStake, "Not enough eth value staked");
            //append the ethAmount to the data we will add to the stakes object
            dataToAppend = abi.encodePacked(dataToAppend, ethAndEigenAmounts.a);
            // emit EthStakeAdded(
            //     operator,
            //     ethAndEigenAmounts.a,
            //     currDumpNumber,
            //     stakeHashUpdates[stakeHashUpdates.length - 1]
            // );
        }

        //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
        if ((registrantType & 0x00000003) == 0x00000003) {
            // if operator want to be an "Eigen" validator, check that they meet the 
            // minimum requirements on how much Eigen it must deposit
            ethAndEigenAmounts.b = uint96(weightOfOperatorEigen(operator));
            require(ethAndEigenAmounts.b >= dlnEigenStake, "Not enough eigen staked");
            //append the eigenAmount to the data we will add to the stakes object
            dataToAppend = abi.encodePacked(dataToAppend, ethAndEigenAmounts.b);
            // emit EigenStakeAdded(
            //     operator,
            //     ethAndEigenAmounts.b,
            //     currDumpNumber,
            //     stakeHashUpdates[stakeHashUpdates.length - 1]
            // );
        }

        //bytes to add to the existing stakes object
        bytes memory dataToAppend = abi.encodePacked(operator, ethAndEigenAmounts.a, ethAndEigenAmounts.b);

        require(ethAndEigenAmounts.a > 0 || ethAndEigenAmounts.b > 0, "must register as at least one type of validator");
        // parse the length 
        /// @dev this is (2) in the description just before the current function 
        uint256 stakesLength = data.toUint256(1);

        // add the tuple (operator address, operator's stake) to the meta-information
        // on the stakes of the existing DataLayr nodes
        // '33' is used here to account for registrantType (already read) and stakesLength
        bytes memory stakes = data.slice(33, stakesLength);

        // stakes must be preimage of last update's hash
        require(
            keccak256(stakes) ==
                stakeHashes[
                    stakeHashUpdates[stakeHashUpdates.length - 1]
                ],
            "Supplied stakes are incorrect"
        );

        stakeHashUpdates.push(currDumpNumber);

        // store the updated meta-data in the mapping with the key being the current dump number
        /** 
         * @dev append the tuple (operator's address, operator's ETH deposit in EigenLayr)
         *      at the front of the list of tuples pertaining to existing DataLayr nodes. 
         *      Also, need to update the total ETH and/or EIGEN deposited by all DataLayr nodes.
         */
        stakeHashes[currDumpNumber] = keccak256(
            abi.encodePacked(
                stakes.slice(0, stakes.length - 24),
                // append at the end of list
                dataToAppend,
                // update the total ETH deposited
                stakes.toUint96(stakes.length - 24) + ethAndEigenAmounts.a,
                // update the total EIGEN deposited
                stakes.toUint96(stakes.length - 12) + ethAndEigenAmounts.b
            )
        );

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
                    //begin just after byte where socket length is specified
                    (34 + stakesLength),
                    //fetch byte that specifies socket length
                    data.toUint8(33 + stakesLength)
                )
            )
        });

        // record the operator being registered
        registrantList.push(operator);

        // update the counter for registrant ID
        unchecked {
            ++nextRegistrantId;
        }

        //TODO: change return type to uint96
        return (registrantType, uint128(ethAndEigenAmounts.b));

        // CRITIC: there should be event here?
        emit StakeAdded(
            operator,
            ethAndEigenAmounts.a,
            ethAndEigenAmounts.b,
            currDumpNumber,
            stakeHashUpdates[stakeHashUpdates.length - 1]
        );
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


//TODO: THIS IS BROKEN -- FIX IT!!!
    /**
     * @notice Used for updating information on ETH and EIGEN deposits of DataLayr nodes. 
     */
    /**
     * @param stakes is the meta-data on the existing DataLayr nodes' addresses and 
     *        their ETH and/or EIGEN deposits. This param is in abi-encodedPacked form of the list of 
     *        the form 
     *          (dln1's registrantType, dln1's addr, dln1's ETH deposit and/or dln1's EIGEN deposit),
     *          (dln2's registrantType, dln2's addr, dln2's ETH deposit and/or dln2's EIGEN deposit), ...
     * @param operators are the DataLayr nodes whose information on their ETH and/or EIGEN deposits
     *        getting updated
     * @param indexes are the tuple positions whose corresponding ETH and/or EIGEN deposit is 
     *        getting updated  
     */ 
    function updateStakes(
        bytes memory stakes,
        address[] memory operators,
        uint32[] memory indexes
    ) public {
        //stakes must be preimage of last update's hash
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
            IDataLayrServiceManager(address(queryManager.feeManager()))
                .dumpNumber(),
            stakeHashUpdates[stakeHashUpdates.length - 1]
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
