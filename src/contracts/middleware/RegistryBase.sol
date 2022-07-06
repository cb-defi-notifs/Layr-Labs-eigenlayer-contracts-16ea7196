// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.9;

// import "../interfaces/IRegistry.sol";
// import "../interfaces/IRepository.sol";
// import "../permissions/RepositoryAccess.sol";

// /**
//  * @notice Simple Implementation of the IRegistry Interface. Handles registration and deregistration, as well as
//  *          storing ETH and EIGEN stakes of registered nodes.
//  */
// contract RegistryBase is IRegistry, RepositoryAccess {
//     /**
//      * @notice struct for storing the amount of Eigen and ETH that has been staked, as well as additional data
//      *          packs two uint96's into a single storage slot
//      */
//     struct EthAndEigenAmounts {
//         uint96 ethAmount;
//         uint96 eigenAmount;
//     }

//     // variable for storing total ETH and Eigen staked into securing the middleware
//     EthAndEigenAmounts public totalStake;

//     // mapping from each operator's address to its Stake for the middleware
//     mapping(address => EthAndEigenAmounts) public operatorStakes;

//     mapping(address => uint8) public operatorType;

//     //TODO: do we need this variable?
//     // number of registrants of this service
//     uint64 public numRegistrants;

//     /**
//      * @notice
//      */
//     event Registration(
//         address registrant,
//         uint256[4] pk,
//         uint32 apkHashIndex,
//         bytes32 apkHash
//     );

//     event DeregistrationCommit(
//         address registrant // who started
//     );

//     constructor(IRepository _repository) 
//         RepositoryAccess(_repository)
//     {
//     }

//     /// @notice get total ETH staked for securing the middleware
//     function totalEthStaked() public view returns (uint96) {
//         return totalStake.ethAmount;
//     }

//     /// @notice get total Eigen staked for securing the middleware
//     function totalEigenStaked() public view returns (uint96) {
//         return totalStake.eigenAmount;
//     }

//     /// @notice get total ETH staked by delegators of the operator
//     function ethStakedByOperator(address operator)
//         public
//         view
//         returns (uint96)
//     {
//         return operatorStakes[operator].ethAmount;
//     }

//     /// @notice get total Eigen staked by delegators of the operator
//     function eigenStakedByOperator(address operator)
//         public
//         view
//         returns (uint96)
//     {
//         return operatorStakes[operator].eigenAmount;
//     }

//     function registerOperator()
//         external
//         virtual
//     {
//         // load operator's current stakes
//         EthAndEigenAmounts memory opStake = operatorStakes[msg.sender];
//         require(opStake.ethAmount == 0 && opStake.eigenAmount == 0, "operator already registered");
//         // get msg.sender's vote weights
//         IVoteWeigher voteWeigher = repository.voteWeigher();
//         opStake.ethAmount = voteWeigher.weightOfOperator(msg.sender, 0);
//         opStake.eigenAmount = voteWeigher.weightOfOperator(msg.sender, 1);
//         // update total stake
//         totalStake.ethAmount += opStake.ethAmount;
//         totalStake.eigenAmount += opStake.eigenAmount;
//         // store the operator's stake in storage
//         operatorStakes[msg.sender] = opStake;
//     }

//     /**
//      * @notice Used by an operator to de-register itself from providing service to the middleware.
//      */
//     function deregisterOperator()
//         external
//         virtual
//         returns (bool)
//     {
// // TODO: verify that the operator can deregister!
//         // load operator's current stakes
//         EthAndEigenAmounts memory opStake = operatorStakes[msg.sender];
//         // update total stake
//         totalStake.ethAmount -= opStake.ethAmount;
//         totalStake.eigenAmount -= opStake.eigenAmount;
//         // zero out the operator's stake in storage
//         operatorStakes[msg.sender] = EthAndEigenAmounts({ethAmount:0, eigenAmount:0});
//         return true;
//     }

//     function isRegistered(address operator) external virtual view returns (bool) {
//         EthAndEigenAmounts memory opStake = operatorStakes[operator];
//         return (opStake.ethAmount > 0 || opStake.eigenAmount > 0);
//     }
// }