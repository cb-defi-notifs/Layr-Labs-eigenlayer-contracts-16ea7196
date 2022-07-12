// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IServiceManager.sol";
import "../../interfaces/IRegistry.sol";
import "../../interfaces/IEphemeralKeyRegistry.sol";
import "../../libraries/BytesLib.sol";
import "../BLSRegistry.sol";

import "ds-test/test.sol";

/**
 * @notice This contract is used for 
            - registering new DataLayr operators 
            - committing to and finalizing de-registration as an operator from DataLayr 
            - updating the stakes of the DataLayr operator
 */

contract DataLayrRegistry is
    BLSRegistry
    // ,DSTest
{
    using BytesLib for bytes;

    IEphemeralKeyRegistry public ephemeralKeyRegistry;

    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        IEphemeralKeyRegistry _ephemeralKeyRegistry,
        StrategyAndWeightingMultiplier[] memory _ethStrategiesConsideredAndMultipliers,
        StrategyAndWeightingMultiplier[] memory _eigenStrategiesConsideredAndMultipliers
    )
        BLSRegistry(
            _repository,
            _delegation,
            _investmentManager,
            _ethStrategiesConsideredAndMultipliers,
            _eigenStrategiesConsideredAndMultipliers
        )
    {
        ephemeralKeyRegistry = _ephemeralKeyRegistry;
    }

    /**
      @notice Used by an operator to de-register itself from providing service to the middleware.
     */
    /** 
      @param pubkeyToRemoveAff is the sender's pubkey in affine coordinates
     */
    function deregisterOperator(uint256[4] memory pubkeyToRemoveAff, uint32 index, bytes32 finalEphemeralKey) external returns (bool) {
        require(
            registry[msg.sender].active > 0,
            "Operator is already registered"
        );

        require(
            msg.sender == registrantList[index],
            "Incorrect index supplied"
        );

        IServiceManager serviceManager = repository.serviceManager();

        // must store till the latest time a dump expires
        /**
         @notice this info is used in forced disclosure
         */
        registry[msg.sender].serveUntil = serviceManager.latestTime();


        // committing to not signing off on any more data that is being asserted into DataLayr
        registry[msg.sender].active = 0;

        registry[msg.sender].deregisterTime = block.timestamp;

        // get current DataStoreId from ServiceManager
        uint32 currentTaskNumber = serviceManager.taskNumber();        
        

        /**
         @notice verify that the sender is a DataLayr operator that is doing deregistration for itself 
         */
        // get operator's stored pubkeyHash
        bytes32 pubkeyHash = registry[msg.sender].pubkeyHash;
        bytes32 pubkeyHashFromInput = keccak256(
            abi.encodePacked(
                pubkeyToRemoveAff[0],
                pubkeyToRemoveAff[1],
                pubkeyToRemoveAff[2],
                pubkeyToRemoveAff[3]
            )
        );
        // verify that it matches the 'pubkeyToRemoveAff' input
        require(pubkeyHash == pubkeyHashFromInput, "incorrect input for commitDeregistration");

        // determine current stakes
        OperatorStake memory currentStakes = pubkeyHashToStakeHistory[
            pubkeyHash
        ][pubkeyHashToStakeHistory[pubkeyHash].length - 1];

        /**
         @notice recording the information pertaining to change in stake for this DataLayr operator in the history
         */
        // determine new stakes
        OperatorStake memory newStakes;
        // recording the current DataStoreId where the operator stake got updated 
        newStakes.updateBlockNumber = uint32(block.number);

        // setting total staked ETH for the DataLayr operator to 0
        newStakes.ethStake = uint96(0);
        // setting total staked Eigen for the DataLayr operator to 0
        newStakes.eigenStake = uint96(0);


        //set next DataStoreId in prev stakes
        pubkeyHashToStakeHistory[pubkeyHash][
            pubkeyHashToStakeHistory[pubkeyHash].length - 1
        ].nextUpdateBlockNumber = uint32(block.number);

        // push new stake to storage
        pubkeyHashToStakeHistory[pubkeyHash].push(newStakes);

        // Update registrant list and update index histories
        popRegistrant(pubkeyHash,index,currentTaskNumber);


        /**
         @notice  update info on ETH and Eigen staked with DataLayr
         */
        // subtract the staked Eigen and ETH of the operator that is getting deregistered from total stake
        // copy total stake to memory
        OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
        _totalStake.ethStake -= currentStakes.ethStake;
        _totalStake.eigenStake -= currentStakes.eigenStake;
        _totalStake.updateBlockNumber = uint32(block.number);
        totalStakeHistory[totalStakeHistory.length - 1].nextUpdateBlockNumber = uint32(block.number);
        totalStakeHistory.push(_totalStake);

        //decrement number of registrants
        unchecked {
            --numRegistrants;
        }


        /**
         @notice update the aggregated public key of all registered DataLayr operators and record
                 this update in history
         */
        // get existing aggregate public key
        uint256[4] memory pk = apk;
        // remove signer's pubkey from aggregate public key
        (pk[0], pk[1], pk[2], pk[3]) = removePubkeyFromAggregate(pubkeyToRemoveAff, pk);
        // update stored aggregate public key
        apk = pk;

        // update aggregated pubkey coordinates
        apkUpdates.push(currentTaskNumber);

        // store hash of updated aggregated pubkey
        apkHashes.push(keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3])));

        //posting last ephemeral key reveal on chain
        ephemeralKeyRegistry.postFirstEphemeralKeyHash(msg.sender, finalEphemeralKey);

        emit Deregistration(msg.sender);
        return true;
    }

    /**
     @notice called for registering as a DataLayr operator
     */
    /**
     @param registrantType specifies whether the DataLayr operator want to register as ETH staker or Eigen stake or both
     @param data is the calldata that contains the coordinates for pubkey on G2 and signature on G1
     @param socket is the socket address of the DataLayr operator
     
     */ 
    function registerOperator(
        uint8 registrantType,
        bytes32 ephemeralKey,
        bytes calldata data,
        string calldata socket
    ) public {        
        _registerOperator(msg.sender, registrantType, ephemeralKey, data, socket);
    }

    /**
     @param operator is the node who is registering to be a DataLayr operator
     */
    function _registerOperator(
        address operator,
        uint8 registrantType,
        bytes32 ephemeralKey,
        bytes calldata data,
        string calldata socket
    ) internal {
        require(
            registry[operator].active == 0,
            "Operator is already registered"
        );

        // TODO: shared struct type for this + registrantType, also used in Repository?
        OperatorStake memory _operatorStake;



        // if first bit of registrantType is '1', then operator wants to be an ETH validator
        if ((registrantType & 1) == 1) {
            // if operator want to be an "ETH" validator, check that they meet the
            // minimum requirements on how much ETH it must deposit
            _operatorStake.ethStake = uint96(weightOfOperatorEth(operator));
            require(
                _operatorStake.ethStake >= nodeEthStake,
                "Not enough eth value staked"
            );
        }

        //if second bit of registrantType is '1', then operator wants to be an EIGEN validator
        if ((registrantType & 2) == 2) {
            // if operator want to be an "Eigen" validator, check that they meet the
            // minimum requirements on how much Eigen it must deposit
            _operatorStake.eigenStake = uint96(weightOfOperatorEigen(operator));
            require(
                _operatorStake.eigenStake >= nodeEigenStake,
                "Not enough eigen staked"
            );
        }

        require(
            _operatorStake.ethStake > 0 || _operatorStake.eigenStake > 0,
            "must register as at least one type of validator"
        );


        
        /**
         @notice evaluate the new aggregated pubkey
         */
        uint256[4] memory newApk;
        uint256[4] memory pk;

        

        {
            // verify sig of public key and get pubkeyHash back, slice out compressed apk
            (pk[0], pk[1], pk[2], pk[3]) = BLS.verifyBLSSigOfPubKeyHash(data, 164);
            
            // add pubkey to aggregated pukkey in Jacobian coordinates
            uint256[6] memory newApkJac = BLS.addJac([pk[0], pk[1], pk[2], pk[3], 1, 0], [apk[0], apk[1], apk[2], apk[3], 1, 0]);
            
            // convert back to Affine coordinates
            (newApk[0], newApk[1], newApk[2], newApk[3]) = BLS.jacToAff(newApkJac);

            apk = newApk;
        }
        

        // getting pubkey hash 
        bytes32 pubkeyHash = keccak256(abi.encodePacked(pk[0], pk[1], pk[2], pk[3]));


        // CRITIC: @Gautham please elaborate on the meaning of this snippet
        if (apkUpdates.length != 0) {
            // addition doesn't work in this case 
            require(pubkeyHash != apkHashes[apkHashes.length - 1], "Apk and pubkey cannot be the same");
        }

        
        // emit log_bytes(getCompressedApk());
        // emit log_named_uint("x", input[0]);
        // emit log_named_uint("y", getYParity(input[0], input[1]) ? 0 : 1);



        
        /**
         @notice some book-keeping for aggregated pubkey
         */
        // get current DataStoreId from ServiceManager
        uint32 currentTaskNumber = repository.serviceManager().taskNumber();

        // store the current DataStoreId in which the aggregated pubkey is being updated 
        apkUpdates.push(uint32(block.number));
        
        //store the hash of aggregate pubkey
        bytes32 newApkHash = keccak256(abi.encodePacked(newApk[0], newApk[1], newApk[2], newApk[3]));
        apkHashes.push(newApkHash);


        

        /**
         @notice some book-keeping for recording info pertaining to the DataLayr operator
         */
        // record the new stake for the DataLayr operator in the storage
        _operatorStake.updateBlockNumber = uint32(block.number);
        pubkeyHashToStakeHistory[pubkeyHash].push(_operatorStake);
        
        // store the registrant's info in relation to DataLayr
        registry[operator] = Registrant({
            pubkeyHash: pubkeyHash,
            id: nextRegistrantId,
            index: numRegistrants,
            active: registrantType,
            fromTaskNumber: currentTaskNumber,
            serveUntil: 0,
            // extract the socket address
            socket: socket,
            deregisterTime: 0
        });

        // record the operator being registered
        registrantList.push(operator);

        // record operator's index in list of operators
        OperatorIndex memory operatorIndex;
        operatorIndex.index = uint32(registrantList.length - 1);
        pubkeyHashToIndexHistory[pubkeyHash].push(operatorIndex);
        

        {
            // Update totalOperatorsHistory
            // set the 'to' field on the last entry *so far* in 'totalOperatorsHistory'
            totalOperatorsHistory[totalOperatorsHistory.length - 1].toTaskNumber = currentTaskNumber;
            // push a new entry to 'totalOperatorsHistory', with 'index' field set equal to the new amount of operators
            OperatorIndex memory _totalOperators;
            _totalOperators.index = uint32(registrantList.length);
            totalOperatorsHistory.push(_totalOperators);
        }

        // update the counter for registrant ID
        unchecked {
            ++nextRegistrantId;
        }
        
        
        {
            /**
            @notice some book-keeping for recoding updated total stake
            */
            OperatorStake memory _totalStake = totalStakeHistory[totalStakeHistory.length - 1];
            /**
            * update total Eigen and ETH that are being employed by the operator for securing
            * the queries from middleware via EigenLayr
            */
            _totalStake.ethStake += _operatorStake.ethStake;
            _totalStake.eigenStake += _operatorStake.eigenStake;
            _totalStake.updateBlockNumber = uint32(block.number);
            // linking with the most recent stake recordd in the past
            totalStakeHistory[totalStakeHistory.length - 1].nextUpdateBlockNumber = uint32(block.number);
            totalStakeHistory.push(_totalStake);
        }

        // increment number of registrants
        unchecked {
            ++numRegistrants;
        }
    

        
        //add ephemeral key to epehemral key registry
        ephemeralKeyRegistry.postFirstEphemeralKeyHash(operator, ephemeralKey);
        
        emit Registration(operator, pk, uint32(apkHashes.length)-1, newApkHash);
    }

    function registerOperator(
        uint8,
        bytes calldata,
        string calldata
    ) public override pure {        
        revert("must register with ephemeral key");
    }

    function deregisterOperator(uint256[4] memory, uint32) external override pure returns (bool) {
        revert("must deregister with ephemeral key");
        return false;
    }
}