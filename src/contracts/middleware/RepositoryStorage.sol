// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRegistry.sol";
import "../interfaces/IInvestmentStrategy.sol";
import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IRepository.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice This contract specifies all the state variables that are being used 
 *         within Repository contract.
 */
abstract contract RepositoryStorage is Ownable, IRepository {
    IEigenLayrDelegation public immutable delegation;
    IInvestmentManager public immutable investmentManager;
    IVoteWeigher public voteWeigher;
    IRegistry public registry;
    IServiceManager public serviceManager;

    constructor (IEigenLayrDelegation _delegation, IInvestmentManager _investmentManager) {
        delegation = _delegation;
        investmentManager = _investmentManager;
    }

    /// @notice returns the owner of the repository contract
    function owner() public view override(Ownable, IRepository) returns (address) {
        return Ownable.owner();
    }
}