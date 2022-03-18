// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../interfaces/IInvestmentStrategy.sol";
import "../../interfaces/IInvestmentManager.sol";
import "../../interfaces/IEigenLayrDelegation.sol";
import "../../interfaces/IQueryManager.sol";

abstract contract QueryManagerStorage is IQueryManager {
    struct Query {
        //hash(reponse) with the greatest cumulative weight
        bytes32 leadingResponse;
        //hash(finalized response). initialized as 0x0, updated if/when query is finalized
        bytes32 outcome;
        //sum of all cumulative weights
        uint256 totalCumulativeWeight;
        //hash(response) => cumulative weight
        mapping(bytes32 => uint256) cumulativeWeights;
        //operator => hash(response)
        mapping(address => bytes32) responses;
        //operator => weight
        mapping(address => uint256) operatorWeights;
    }

    IEigenLayrDelegation public delegation;
    IInvestmentManager public investmentManager;
    mapping(IInvestmentStrategy => uint256) public shares;
    mapping(address => mapping(IInvestmentStrategy => uint256))
        public operatorShares;
    mapping(address => IInvestmentStrategy[]) public operatorStrats;
    mapping(address => uint256) public eigenDeposited;
    IInvestmentStrategy[] public strats;
    uint256 public consensusLayerEthToEth;
    mapping(address => uint256) public consensusLayerEth;
    uint256 public totalConsensusLayerEth;
    uint256 public totalEigen;
    //fixed duration of all new queries
    uint256 public queryDuration;
    //called when new queries are created. handles payments for queries.
    IFeeManager public feeManager;
    //timelock address which has control over upgrades of feeManager
    address public timelock;
    // number of registrants of this service
    uint256 public numRegistrants;
    //map from registrant address to whether they are active or not
    mapping(address => uint8) public registrantType;
    address public registrationManager;
    //hash(queryData) => Query
    mapping(bytes32 => Query) public queries;
    //hash(queryData) => time query created
    mapping(bytes32 => uint256) public queriesCreated;
    bytes32[] public activeQueries;
}