// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IERC20.sol";
import "../../interfaces/ProofOfStakingInterfaces.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../QueryManager.sol";

contract ProofOfStakingServiceManager is IFeeManager, IProofOfStakingServiceManager {
    IVoteWeighter public voteWeighter;
    IProofOfStakingRegVW public posRegVW;
    IEigenLayrDelegation public eigenLayrDelegation;
    IERC20 public token;
    uint256 public fee;
    IQueryManager public queryManager;
    uint256 public totalFees;
    uint256 public BIG_NUMBER = 10e50;
    mapping(address => uint256) public operatorToLastFees;

    constructor(
        IEigenLayrDelegation _eigenLayrDelegation,
        IVoteWeighter _voteWeighter,
        IERC20 _token,
        IProofOfStakingRegVW _posRegVW
    ) {
        eigenLayrDelegation = _eigenLayrDelegation;
        voteWeighter = _voteWeighter;
        token = _token;
        posRegVW = _posRegVW;
    }

    function setQueryManager(IQueryManager _queryManager) public {
        require(
            address(queryManager) == address(0),
            "Query Manager already set"
        );
        queryManager = _queryManager;
    }

    function setFee(uint256 _fee) public {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        fee = _fee;
    }

    function payFee(address payer) external payable {
        require(
            msg.sender == address(queryManager),
            "Only the query manager can call this function"
        );
        totalFees += BIG_NUMBER * fee / posRegVW.totalEth();
        token.transferFrom(payer, address(this), fee);
    }

    function redeemPayment(address operator) external {
        require(msg.sender == operator || msg.sender == address(posRegVW), "only operator or posRegVW can redeem fees");
        uint256 payment = posRegVW.getEtherForOperator(operator) * (totalFees - operatorToLastFees[operator]);
        operatorToLastFees[operator] = totalFees;
        IDelegationTerms dt = eigenLayrDelegation.getDelegationTerms(operator);
        token.transfer(address(dt), payment);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = payment;
        eigenLayrDelegation.getDelegationTerms(operator).payForService(queryManager, tokens, amounts);
    }

    function getLastFees(address operator) external view returns (uint256) {
        return operatorToLastFees[operator];
    }

    function setLastFeesForOperator(address operator) external {
        require(msg.sender == address(posRegVW), "POSRegVW can only set last fees");
        operatorToLastFees[operator] = totalFees;
    }

    function onResponse(
        bytes32 queryHash,
        address operator,
        bytes32 reponseHash,
        uint256 senderWeight
    ) external {}
}
