// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IDataLayrServiceManager.sol";
import "../../libraries/BytesLib.sol";
import "../Repository.sol";
import "../VoteWeigherBase.sol";
import "../RegistrationManagerBaseMinusRepository.sol";
import "../../libraries/SignatureCompaction.sol";

import "ds-test/test.sol";

/**
 * @notice
 */

contract DataLayrVoteWeigher is VoteWeigherBase, RegistrationManagerBaseMinusRepository, DSTest {
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
     * @notice pack two uint48's into a storage slot
     */
    struct Uint48xUint48 {
        uint48 a;
        uint48 b;
    }

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId)");
    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant REGISTRATION_TYPEHASH = keccak256("Registration(address operator,address registrationContract,uint256 expiry)");
    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

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

    // EVENTS
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
        Repository _repository,
        IEigenLayrDelegation _delegation,
        uint256 _consensusLayerEthToEth
    ) VoteWeigherBase(_repository, _delegation, _consensusLayerEthToEth) {
        //initialize the stake object
        stakeHashUpdates.push(0);
        //input is length 24 zero bytes (12 bytes each for ETH & EIGEN totals, which both start at 0)
        bytes32 zeroHash = keccak256(abi.encodePacked(bytes24(0)));
        //initialize the mapping
        stakeHashes[0] = zeroHash;
        //initialize the DOMAIN_SEPARATOR for signatures
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid));
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
     * @notice Used for notifying that operator wants to deregister from being 
     *         a DataLayr node 
     */
    function commitDeregistration() external returns (bool) {
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
// TODO: JEFFC -- delete operator out of stakes object (replace them with the last person & pop off the data)
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

        uint256 operatorsLength = operators.length;
        require(
            indexes.length == operatorsLength,
            "operator len and index len don't match"
        );

        // get dump number from DataLayrServiceManagerStorage.sol
        Uint48xUint48 memory dumpNumbers = Uint48xUint48(
            IDataLayrServiceManager(address(repository.serviceManager()))
                .dumpNumber(),
            stakeHashUpdates[stakeHashUpdates.length - 1]
        );

        // iterating over all the tuples that are to be updated
        for (uint256 i = 0; i < operatorsLength; ) {

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
            address(repository.serviceManager()) == msg.sender,
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


    /// @notice returns the type for the specified operator
    function getOperatorType(address operator)
        public
        view
        returns (uint8)
    {
        return registry[operator].active;
    }
















    function registerOperator(uint8 registrantType, string calldata socket, bytes calldata stakes) public {
        _registerOperator(msg.sender, registrantType, socket, stakes);
    }

    function registerOperatorBySignature(
        address operator,
        uint8 registrantType,
        string calldata socket,
        uint256 expiry,
        bytes32 r,
        bytes32 vs,
        bytes calldata stakes
        ) external
    {
        require(expiry == 0 || expiry <= block.timestamp, "registration signature expired");
        bytes32 structHash = keccak256(
            abi.encode(
                REGISTRATION_TYPEHASH,
                operator,
                address(this),
                expiry
            )
        );
        bytes32 digestHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                structHash
            )
        );
        //check validity of signature
        address recoveredAddress = SignatureCompaction.ecrecoverPacked(digestHash, r, vs);
        require(recoveredAddress != address(0), "registerOperatorBySignature: bad signature");
        require(recoveredAddress == operator, "registerOperatorBySignature: sig not from operator");

        _registerOperator(operator, registrantType, socket, stakes);
    }

    function _registerOperator(address operator, uint8 registrantType, string calldata socket, bytes calldata stakes) internal {
        require(
            registry[operator].active == 0,
            "Operator is already registered"
        );

        // TODO: shared struct type for this + registrantType, also used in Repository?
        EthAndEigenAmounts memory _operatorStake;

        //if first bit of registrantType is '1', then operator wants to be an ETH validator
        if ((registrantType & 0x00000001) == 0x00000001) {
            // if operator want to be an "ETH" validator, check that they meet the 
            // minimum requirements on how much ETH it must deposit
            _operatorStake.ethAmount = uint96(weightOfOperatorEth(operator));
            require(_operatorStake.ethAmount >= dlnEthStake, "Not enough eth value staked");
        }

        //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
        if ((registrantType & 0x00000002) == 0x00000002) {
            // if operator want to be an "Eigen" validator, check that they meet the 
            // minimum requirements on how much Eigen it must deposit
            _operatorStake.eigenAmount = uint96(weightOfOperatorEigen(operator));
            require(_operatorStake.eigenAmount >= dlnEigenStake, "Not enough eigen staked");
        }

        //bytes to add to the existing stakes object
        bytes memory dataToAppend = abi.encodePacked(operator, _operatorStake.ethAmount, _operatorStake.eigenAmount);

        require(_operatorStake.ethAmount > 0 || _operatorStake.eigenAmount > 0, "must register as at least one type of validator");

        require(
            keccak256(stakes) == stakeHashes[stakeHashUpdates[stakeHashUpdates.length - 1]],
            "Supplied stakes are incorrect"
        );

        // slice starting the byte after socket length to construct the details on the 
        // DataLayr node
        registry[operator] = Registrant({
            id: nextRegistrantId,
            index: numRegistrants,
            active: registrantType,
            fromDumpNumber: IDataLayrServiceManager(
                address(repository.serviceManager())
            ).dumpNumber(),
            to: 0,
            // extract the socket address 
            socket: socket
        });

        // record the operator being registered
        registrantList.push(operator);

        // update the counter for registrant ID
        unchecked {
            ++nextRegistrantId;
        }

        // get current dump number from DataLayrServiceManager
        uint48 currentDumpNumber = IDataLayrServiceManager(
            address(repository.serviceManager())
        ).dumpNumber();

        emit StakeAdded(operator, _operatorStake.ethAmount, _operatorStake.eigenAmount, stakeHashUpdates.length, currentDumpNumber, stakeHashUpdates[stakeHashUpdates.length - 1]);

        stakeHashUpdates.push(currentDumpNumber);

        // update operator stake in storage
        operatorStakes[operator] = _operatorStake;

        // copy total stake to memory
        EthAndEigenAmounts memory _totalStake = totalStake;
        /**
         * update total Eigen and ETH that are being employed by the operator for securing
         * the queries from middleware via EigenLayr
         */
        _totalStake.ethAmount += _operatorStake.ethAmount;
        _totalStake.eigenAmount += _operatorStake.eigenAmount;
        // update storage of total stake
        totalStake = _totalStake;

        //TODO: do we need this variable at all?
        //increment number of registrants
        unchecked {
            ++numRegistrants;
        }

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
                // update the total ETH and EIGEN deposited
                _totalStake.ethAmount,
                _totalStake.eigenAmount
            )
        );
    }

    function registerOperatorsBySignatures(
        address[] calldata operators,
        uint8[] calldata registrantTypes,
        string[] calldata sockets,
        uint256[] calldata expiries,
        // set of all {r, vs} for signers
        bytes32[] calldata signatureData,
        bytes calldata stakes) 
        external
    {
        // check all the signatures
        // uint256 operatorsLength = operators.length;
        // for (uint256 i = 0; i < operatorsLength;) {
        for (uint256 i = 0; i < operators.length;) {
            require(expiries[i] == 0 || expiries[i] <= block.timestamp, "registration signature expired");
            bytes32 structHash = keccak256(
                abi.encode(
                    REGISTRATION_TYPEHASH,
                    operators[i],
                    address(this),
                    expiries[i]
                )
            );
            bytes32 digestHash = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    structHash
                )
            );
            //check validity of signature
            address recoveredAddress = SignatureCompaction.ecrecoverPacked(digestHash, signatureData[2 * i], signatureData[2 * i + 1]);
            require(recoveredAddress != address(0), "registerOperatorBySignature: bad signature");
            require(recoveredAddress == operators[i], "registerOperatorBySignature: sig not from operator");

            // increment loop
            unchecked {
                ++i;
            }
        }
        _registerOperators(operators, registrantTypes, sockets, stakes);
    }
    
    function _registerOperators(address[] calldata operators, uint8[] calldata registrantTypes, string[] calldata sockets, bytes calldata stakes) internal {
        require(
            keccak256(stakes) == stakeHashes[stakeHashUpdates[stakeHashUpdates.length - 1]],
            "Supplied stakes are incorrect"
        );        
        // copy total stake to memory
        EthAndEigenAmounts memory _totalStake = totalStake;

        //bytes to add to the existing stakes object
        bytes memory dataToAppend;

        // get current dump number from DataLayrServiceManager
        uint48 currentDumpNumber = IDataLayrServiceManager(
            address(repository.serviceManager())
        ).dumpNumber(); 

        // uint256 operatorsLength = operators.length;
        // for (uint256 i = 0; i < operatorsLength;) {
        for (uint256 i = 0; i < operators.length;) { 
            require(
                registry[operators[i]].active == 0,
                "Operator is already registered"
            );

            // TODO: shared struct type for this + registrantType, also used in Repository?
            EthAndEigenAmounts memory _operatorStake;

            //if first bit of registrantType is '1', then operator wants to be an ETH validator
            if ((registrantTypes[i] & 0x00000001) == 0x00000001) {
                // if operator want to be an "ETH" validator, check that they meet the 
                // minimum requirements on how much ETH it must deposit
                _operatorStake.ethAmount = uint96(weightOfOperatorEth(operators[i]));
                require(_operatorStake.ethAmount >= dlnEthStake, "Not enough eth value staked");
            }   

            //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
            if ((registrantTypes[i] & 0x00000002) == 0x00000002) {
                // if operator want to be an "Eigen" validator, check that they meet the 
                // minimum requirements on how much Eigen it must deposit
                _operatorStake.eigenAmount = uint96(weightOfOperatorEigen(operators[i]));
                require(_operatorStake.eigenAmount >= dlnEigenStake, "Not enough eigen staked");
            }   

            require(_operatorStake.ethAmount > 0 || _operatorStake.eigenAmount > 0, "must register as at least one type of validator");

            // add operator's info to the 'dataToAppend' object
            dataToAppend = abi.encodePacked(dataToAppend, operators[i], _operatorStake.ethAmount, _operatorStake.eigenAmount);

            // slice starting the byte after socket length to construct the details on the 
            // DataLayr node
            registry[operators[i]] = Registrant({
                id: nextRegistrantId,
                index: numRegistrants,
                active: registrantTypes[i],
                fromDumpNumber: currentDumpNumber,
                to: 0,
                // extract the socket address 
                socket: sockets[i]
            });

            // record the operator being registered
            registrantList.push(operators[i]);  

            // update the counter for registrant ID
            unchecked {
                ++nextRegistrantId;
            }   

            emit StakeAdded(operators[i], _operatorStake.ethAmount, _operatorStake.eigenAmount, stakeHashUpdates.length, currentDumpNumber, stakeHashUpdates[stakeHashUpdates.length - 1]); 

            // update operator stake in storage
            operatorStakes[operators[i]] = _operatorStake;  

            /**
             * update total Eigen and ETH that are being employed by the operator for securing
             * the queries from middleware via EigenLayr
             */
            _totalStake.ethAmount += _operatorStake.ethAmount;
            _totalStake.eigenAmount += _operatorStake.eigenAmount;

            //TODO: do we need this variable at all?
            //increment number of registrants
            unchecked {
                ++numRegistrants;
            }   

            // increment the loop
            unchecked {
                ++i;
            }
        }

        // update storage of total stake
        totalStake = _totalStake;   

        stakeHashUpdates.push(currentDumpNumber);  

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
                // update the total ETH and EIGEN deposited
                _totalStake.ethAmount,
                _totalStake.eigenAmount
            )
        );
    }
}