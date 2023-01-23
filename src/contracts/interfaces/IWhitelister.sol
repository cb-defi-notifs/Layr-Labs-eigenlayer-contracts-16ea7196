// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "../../contracts/interfaces/IInvestmentManager.sol";
import "../../contracts/interfaces/IInvestmentStrategy.sol";
import "../../contracts/interfaces/IEigenLayerDelegation.sol";
import "../../contracts/interfaces/IBLSRegistry.sol";
import "../../../script/whitelist/Staker.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";


interface IWhitelister {

    function whitelist(address operator) external;

    function getStaker(address operator) external returns (address);

    function depositIntoStrategy(
        address staker,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount
    ) external returns (bytes memory);

    function queueWithdrawal(
        address staker,
        uint256[] calldata strategyIndexes,
        IInvestmentManager.StratsTokensShares calldata sts,
        address withdrawer,
        bool undelegateIfPossible
    ) external returns (bytes memory);

    function completeQueuedWithdrawal(
        address staker,
        IInvestmentManager.QueuedWithdrawal calldata queuedWithdrawal,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) external returns (bytes memory);

    function transfer(
        address staker,
        address token,
        address to,
        uint256 amount
    ) external returns (bytes memory) ; 
    
    function callAddress(
        address to,
        bytes memory data
    ) external payable returns (bytes memory);
}
