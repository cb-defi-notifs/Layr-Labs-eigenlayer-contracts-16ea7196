// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "./ServiceManagerStorage.sol";
import "../interfaces/IVoteWeigher.sol";
import "../interfaces/ITaskMetadata.sol";
import "../interfaces/ISlasher.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../permissions/RepositoryAccess.sol";

contract ServiceManagerBase is ServiceManagerStorage, Initializable, RepositoryAccess {
    /**
     * @notice This struct is used for containing the details of a task that is created 
     *         by the middleware for validation in EigenLayr.
     */

    /**************************
        DATA STRUCTURES
     **************************/ 

    /// @notice contains details of the task  
    struct Task {
        // hash(reponse) with the greatest cumulative weight
        bytes32 leadingResponse;
        // hash(finalized response). initialized as 0x0, updated if/when task is finalized
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
    IInvestmentManager public immutable investmentManager;
    IEigenLayrDelegation public immutable eigenLayrDelegation;
    
    /// @notice fixed duration of all new tasks
    uint256 public taskDuration;

    /**
     * @notice Hash of each task is mapped to the corresponding creation time of the task.
     */
    mapping(bytes32 => uint256) public taskCreated;

    /**
     * @notice Each task is mapped to its hash, which is used as its identifier.
     */
    mapping(bytes32 => Task) public tasks;


    /*****************
        EVENTS
     *****************/
    event TaskCreated(bytes32 indexed taskDataHash, uint256 blockTimestamp);

    event ResponseReceived(
        address indexed submitter,
        bytes32 indexed taskDataHash,
        bytes32 indexed responseHash,
        uint256 weightAssigned
    );

    event NewLeadingResponse(
        bytes32 indexed taskDataHash,
        bytes32 indexed previousLeadingResponseHash,
        bytes32 indexed newLeadingResponseHash
    );
    
    event TaskFinalized(
        bytes32 indexed taskDataHash,
        bytes32 indexed outcome,
        uint256 totalCumulativeWeight
    );

    constructor(
        IERC20 _paymentToken,
        IERC20 _collateralToken,
        IRepository _repository,
        IInvestmentManager _investmentManager,
        IEigenLayrDelegation _eigenLayrDelegation
    )
        ServiceManagerStorage(_paymentToken, _collateralToken)
        RepositoryAccess(_repository)
    {
        investmentManager = _investmentManager;
        eigenLayrDelegation = _eigenLayrDelegation;
        // TODO: uncomment for production use!
        //_disableInitializers();
    }

    function initialize(
        IVoteWeigher _voteWeigher,
        ITaskMetadata _taskMetadata
    )  external initializer {
        voteWeigher = _voteWeigher;
        taskMetadata = _taskMetadata;
    }

    /**
     * @notice creates a new task based on the @param taskData passed.
     */
    // CRITIC: if we end up maintaining a database of registered middlewares (whitelisting) in EigenLayr contracts,
    //         then it might be good (necessary?) to only ensure a middleware can call this function.
    function createNewTask(bytes calldata taskData) external {
        _createNewTask(msg.sender, taskData);
    }

    function _createNewTask(address taskCreator, bytes calldata taskData)
        internal
    {
        bytes32 taskDataHash = keccak256(taskData);

        //verify that task has not already been created
        require(taskCreated[taskDataHash] == 0, "duplicate task");

        //mark task as created and emit an event
        taskCreated[taskDataHash] = block.timestamp;
        emit TaskCreated(taskDataHash, block.timestamp);

        //TODO: fee calculation of any kind
        uint256 fee;

        //hook to manage payment for task
        paymentToken.transferFrom(taskCreator, address(this), fee);
    }

    /**
     * @notice Used by operators to respond to a specific task.
     */
    /**
     * @param taskHash is the identifier for the task to which the operator is responding,
     * @param response is the operator's response for the task.
     */
    function respondToTask(bytes32 taskHash, bytes calldata response)
        external
    {
        _respondToTask(msg.sender, taskHash, response);
    }

    function _respondToTask(
        address respondent,
        bytes32 taskHash,
        bytes calldata response
    ) internal {
        // make sure task is open
        require(block.timestamp < _taskExpiry(taskHash), "task period over");

        // make sure sender has not already responded to it
        require(
            tasks[taskHash].operatorWeights[respondent] == 0,
            "duplicate response to task"
        );

        // find respondent's weight and the hash of their response
        uint256 weightToAssign = voteWeigher.weightOfOperator(respondent, 0);
        bytes32 responseHash = keccak256(response);

        // update Task struct with respondent's weight and response
        tasks[taskHash].operatorWeights[respondent] = weightToAssign;
        tasks[taskHash].responses[respondent] = responseHash;
        tasks[taskHash].cumulativeWeights[responseHash] += weightToAssign;
        tasks[taskHash].totalCumulativeWeight += weightToAssign;

        //emit event for response
        emit ResponseReceived(
            respondent,
            taskHash,
            responseHash,
            weightToAssign
        );

        // check if leading response has changed. if so, update leadingResponse and emit an event
        bytes32 leadingResponseHash = tasks[taskHash].leadingResponse;
        if (
            responseHash != leadingResponseHash &&
            tasks[taskHash].cumulativeWeights[responseHash] >
            tasks[taskHash].cumulativeWeights[leadingResponseHash]
        ) {
            tasks[taskHash].leadingResponse = responseHash;
            emit NewLeadingResponse(
                taskHash,
                leadingResponseHash,
                responseHash
            );
        }
    }

    /**
     * @notice Used for finalizing the outcome of the task associated with the taskHash
     */
    function finalizeTask(bytes32 taskHash) external {
        // make sure taskHash is valid
        require(taskCreated[taskHash] != 0, "invalid taskHash");

        // make sure task period has ended
        require(
            block.timestamp >= _taskExpiry(taskHash),
            "task period ongoing"
        );

        // check that task has not already been finalized,
        // task.outcome is always initialized as 0x0 and set after finalization
        require(
            tasks[taskHash].outcome == bytes32(0),
            "duplicate finalization request"
        );

        // record the leading response as the final outcome and emit an event
        bytes32 outcome = tasks[taskHash].leadingResponse;
        tasks[taskHash].outcome = outcome;
        emit TaskFinalized(
            taskHash,
            outcome,
            tasks[taskHash].totalCumulativeWeight
        );
    }

    function slashOperator(address operator) external {
        revert("function unfinished in this contract -- no permissions");
        ISlasher(investmentManager.slasher()).slashOperator(operator);
    }

    /// @notice returns the outcome of the task associated with the taskHash
    function getTaskOutcome(bytes32 taskHash)
        external
        view
        returns (bytes32)
    {
        return tasks[taskHash].outcome;
    }

    /// @notice returns the duration of time for which an operator can respond to a task
    function getTaskDuration() external view returns (uint256) {
        return taskDuration;
    }

    /// @notice returns the time when the task, associated with taskHash, was created
    function getTaskCreationTime(bytes32 taskHash)
        public
        view
        returns (uint256)
    {
        uint256 timeCreated = taskCreated[taskHash];
        if (timeCreated != 0) {
            return timeCreated;
        } else {
            return type(uint256).max;
        }
    }

    /// @notice returns the time when the task, associated with taskHash, will expire
    function getTaskExpiry(bytes32 taskHash)
        external
        view
        returns (uint256)
    {
        return _taskExpiry(taskHash);
    }

    function _taskExpiry(bytes32 taskHash) internal view returns (uint256) {
        return getTaskCreationTime(taskHash) + taskDuration;
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

// TODO: implement function if possible
    // function stakeWithdrawalVerification(bytes calldata data, uint256 initTimestamp, uint256 unlockTime) external {
    function stakeWithdrawalVerification(bytes calldata, uint256, uint256) external {
       
    }

// TODO: implement function if possible
    function latestTime() external view returns(uint32) {

    }
}
