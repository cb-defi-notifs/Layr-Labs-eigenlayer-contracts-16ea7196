// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "./ServiceManagerStorage.sol";
import "../interfaces/IRepository.sol";
import "../interfaces/IVoteWeigher.sol";
import "../interfaces/ITaskMetadata.sol";

contract ServiceManagerBase is ServiceManagerStorage, Initializable {
    /**
     * @notice This struct is used for containing the details of a serviceObject that is created 
     *         by the middleware for validation in EigenLayr.
     */
    struct ServiceObject {
        // hash(reponse) with the greatest cumulative weight
        bytes32 leadingResponse;
        // hash(finalized response). initialized as 0x0, updated if/when serviceObject is finalized
        bytes32 outcome;
        // sum of all cumulative weights
        uint256 totalCumulativeWeight;
        // hash(response) => cumulative weight
        mapping(bytes32 => uint256) cumulativeWeights;
        // operator => hash(response)
        mapping(address => bytes32) responses;
        // operator => weight
        mapping(address => uint256) operatorWeights;
    }

    IVoteWeigher public voteWeigher;
    ITaskMetadata public taskMetadata;
    
    // fixed duration of all new serviceObjects
    uint256 public serviceObjectDuration;

    /**
     * @notice Hash of each serviceObject is mapped to the corresponding creation time of the serviceObject.
     */
    mapping(bytes32 => uint256) public serviceObjectCreated;

    /**
     * @notice Each serviceObject is mapped to its hash, which is used as its identifier.
     */
    mapping(bytes32 => ServiceObject) public serviceObjects;

    event ServiceObjectCreated(bytes32 indexed serviceObjectDataHash, uint256 blockTimestamp);
    event ResponseReceived(
        address indexed submitter,
        bytes32 indexed serviceObjectDataHash,
        bytes32 indexed responseHash,
        uint256 weightAssigned
    );
    event NewLeadingResponse(
        bytes32 indexed serviceObjectDataHash,
        bytes32 indexed previousLeadingResponseHash,
        bytes32 indexed newLeadingResponseHash
    );
    event ServiceObjectFinalized(
        bytes32 indexed serviceObjectDataHash,
        bytes32 indexed outcome,
        uint256 totalCumulativeWeight
    );
    // only repositoryGovernance can call this, but 'sender' called instead
    error OnlyRepositoryGovernance(
        address repositoryGovernance,
        address sender
    );

// TODO: change to initializer
    constructor(IERC20 _paymentToken, IERC20 _collateralToken) ServiceManagerStorage(_paymentToken, _collateralToken) {
        // TODO: uncomment for production use!
        //_disableInitializers();
    }

    function initialize(
        IRepository _repository,
        IVoteWeigher _voteWeigher,
        ITaskMetadata _taskMetadata
    )  external initializer {
        repository = _repository;
        voteWeigher = _voteWeigher;
        taskMetadata = _taskMetadata;
    }

    /**
     * @notice creates a new serviceObject based on the @param serviceObjectData passed.
     */
    // CRITIC: if we end up maintaining a database of registered middlewares (whitelisting) in EigenLayr contracts,
    //         then it might be good (necessary?) to only ensure a middleware can call this function.
    function createNewServiceObject(bytes calldata serviceObjectData) external {
        _createNewServiceObject(msg.sender, serviceObjectData);
    }

    function _createNewServiceObject(address serviceObjectCreator, bytes calldata serviceObjectData)
        internal
    {
        bytes32 serviceObjectDataHash = keccak256(serviceObjectData);

        //verify that serviceObject has not already been created
        require(serviceObjectCreated[serviceObjectDataHash] == 0, "duplicate serviceObject");

        //mark serviceObject as created and emit an event
        serviceObjectCreated[serviceObjectDataHash] = block.timestamp;
        emit ServiceObjectCreated(serviceObjectDataHash, block.timestamp);

        //TODO: fee calculation of any kind
        uint256 fee;

        //hook to manage payment for serviceObject
        paymentToken.transferFrom(serviceObjectCreator, address(this), fee);
    }

    /**
     * @notice Used by operators to respond to a specific serviceObject.
     */
    /**
     * @param serviceObjectHash is the identifier for the serviceObject to which the operator is responding,
     * @param response is the operator's response for the serviceObject.
     */
    function respondToServiceObject(bytes32 serviceObjectHash, bytes calldata response)
        external
    {
        _respondToServiceObject(msg.sender, serviceObjectHash, response);
    }

    function _respondToServiceObject(
        address respondent,
        bytes32 serviceObjectHash,
        bytes calldata response
    ) internal {
        // make sure serviceObject is open
        require(block.timestamp < _serviceObjectExpiry(serviceObjectHash), "serviceObject period over");

        // make sure sender has not already responded to it
        require(
            serviceObjects[serviceObjectHash].operatorWeights[respondent] == 0,
            "duplicate response to serviceObject"
        );

        // find respondent's weight and the hash of their response
        uint256 weightToAssign = voteWeigher.weightOfOperator(respondent, 0);
        bytes32 responseHash = keccak256(response);

        // update ServiceObject struct with respondent's weight and response
        serviceObjects[serviceObjectHash].operatorWeights[respondent] = weightToAssign;
        serviceObjects[serviceObjectHash].responses[respondent] = responseHash;
        serviceObjects[serviceObjectHash].cumulativeWeights[responseHash] += weightToAssign;
        serviceObjects[serviceObjectHash].totalCumulativeWeight += weightToAssign;

        //emit event for response
        emit ResponseReceived(
            respondent,
            serviceObjectHash,
            responseHash,
            weightToAssign
        );

        // check if leading response has changed. if so, update leadingResponse and emit an event
        bytes32 leadingResponseHash = serviceObjects[serviceObjectHash].leadingResponse;
        if (
            responseHash != leadingResponseHash &&
            serviceObjects[serviceObjectHash].cumulativeWeights[responseHash] >
            serviceObjects[serviceObjectHash].cumulativeWeights[leadingResponseHash]
        ) {
            serviceObjects[serviceObjectHash].leadingResponse = responseHash;
            emit NewLeadingResponse(
                serviceObjectHash,
                leadingResponseHash,
                responseHash
            );
        }
    }

    /**
     * @notice Used for finalizing the outcome of the serviceObject associated with the serviceObjectHash
     */
    function finalizeServiceObject(bytes32 serviceObjectHash) external {
        // make sure serviceObjectHash is valid
        require(serviceObjectCreated[serviceObjectHash] != 0, "invalid serviceObjectHash");

        // make sure serviceObject period has ended
        require(
            block.timestamp >= _serviceObjectExpiry(serviceObjectHash),
            "serviceObject period ongoing"
        );

        // check that serviceObject has not already been finalized,
        // serviceObject.outcome is always initialized as 0x0 and set after finalization
        require(
            serviceObjects[serviceObjectHash].outcome == bytes32(0),
            "duplicate finalization request"
        );

        // record the leading response as the final outcome and emit an event
        bytes32 outcome = serviceObjects[serviceObjectHash].leadingResponse;
        serviceObjects[serviceObjectHash].outcome = outcome;
        emit ServiceObjectFinalized(
            serviceObjectHash,
            outcome,
            serviceObjects[serviceObjectHash].totalCumulativeWeight
        );
    }

    /// @notice returns the outcome of the serviceObject associated with the serviceObjectHash
    function getServiceObjectOutcome(bytes32 serviceObjectHash)
        external
        view
        returns (bytes32)
    {
        return serviceObjects[serviceObjectHash].outcome;
    }

    /// @notice returns the duration of time for which an operator can respond to a serviceObject
    function getServiceObjectDuration() external view returns (uint256) {
        return serviceObjectDuration;
    }

    /// @notice returns the time when the serviceObject, associated with serviceObjectHash, was created
    function getServiceObjectCreationTime(bytes32 serviceObjectHash)
        public
        view
        returns (uint256)
    {
        uint256 timeCreated = serviceObjectCreated[serviceObjectHash];
        if (timeCreated != 0) {
            return timeCreated;
        } else {
            return type(uint256).max;
        }
    }

    /// @notice returns the time when the serviceObject, associated with serviceObjectHash, will expire
    function getServiceObjectExpiry(bytes32 serviceObjectHash)
        external
        view
        returns (uint256)
    {
        return _serviceObjectExpiry(serviceObjectHash);
    }

    function _serviceObjectExpiry(bytes32 serviceObjectHash) internal view returns (uint256) {
        return getServiceObjectCreationTime(serviceObjectHash) + serviceObjectDuration;
    }

    /**
     @notice this function returns the compressed record on the signatures of  nodes 
             that aren't part of the quorum for this @param _taskNumber.
     */
    function getTaskNumberSignatureHash(uint32 _taskNumber)
        public
        view
        returns (bytes32)
    {
        return taskNumberToSignatureHash[_taskNumber];
    }

    function getPaymentCollateral(address operator)
        public
        view
        returns (uint256)
    {
        return operatorToPayment[operator].collateral;
    }

    modifier onlyRepositoryGovernance() {
        if (!(address(repository.owner()) == msg.sender)) {
            revert OnlyRepositoryGovernance(address(repository.owner()), msg.sender);
        }
        _;
    }
}
