// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../src/contracts/interfaces/IInvestmentManager.sol";
import "../../src/contracts/interfaces/IInvestmentStrategy.sol";
import "../../src/contracts/interfaces/IEigenLayrDelegation.sol";
import "./Staker.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Whitelister is Ownable {
    address constant invesmentManager = 0x0000000000000000000000000000000000000000;
    //TODO: change before deploy
    ERC20PresetMinterPauser immutable whitelistToken;
    IInvestmentStrategy immutable whitelistStrategy;

    uint256 internal constant DEFAULT_AMOUNT = 100e18;

    mapping(address => Staker) public operatorToStakers;

    constructor(ERC20PresetMinterPauser _whitelistToken, IInvestmentStrategy _whitelistStrategy) {
        whitelistToken = _whitelistToken;
        whitelistStrategy = _whitelistStrategy;
    }

    function whitelist(address operator) public onlyOwner {
        operatorToStakers[operator] = new Staker(whitelistStrategy, whitelistToken, DEFAULT_AMOUNT, operator);
    }

    function depositIntoStrategy(
        address staker, 
        IInvestmentStrategy strategy, 
        IERC20 token, 
        uint256 amount
    ) public onlyOwner returns(bytes memory) {
        bytes memory data = abi.encode(
            address(invesmentManager),
            abi.encodeWithSelector(IInvestmentManager.depositIntoStrategy.selector, strategy, token, amount)
        );

        return _callAddress(staker, data);
    }

    function queueWithdrawal(
        address staker,
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shares,
        address withdrawer,
        bool undelegateIfPossible
    ) public onlyOwner returns(bytes memory) {
        bytes memory data = abi.encode(
            invesmentManager,
            abi.encodeWithSelector(
                IInvestmentManager.queueWithdrawal.selector, 
                strategyIndexes,
                strategies,
                tokens,
                shares,
                withdrawer,
                undelegateIfPossible
            )
        );

        return _callAddress(staker, data);
    }

    function completeQueuedWithdrawal(
        address staker, 
        IInvestmentManager.QueuedWithdrawal calldata queuedWithdrawal, 
        uint256 middlewareTimesIndex, 
        bool receiveAsTokens
    ) public onlyOwner returns(bytes memory) {
        bytes memory data = abi.encode(
            invesmentManager,
            abi.encodeWithSelector(
                IInvestmentManager.completeQueuedWithdrawal.selector, 
                queuedWithdrawal,
                middlewareTimesIndex,
                receiveAsTokens
            )
        );

        return _callAddress(staker, data);
    }

    function transfer(
        address staker, address token, address to, uint256 amount
    ) public onlyOwner returns(bytes memory) {
        bytes memory data = abi.encode(
            token,
            abi.encodeWithSelector(
                IERC20.transfer.selector, 
                to,
                amount
            )
        );

        return _callAddress(staker, data);
    }

    function callAddress(address addr, bytes calldata data) public onlyOwner returns(bytes memory) {
        _callAddress(addr, data);
    }

    function _callAddress(address addr, bytes memory data) internal  returns(bytes memory) {
        assembly {
            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := call(gas(), addr, callvalue(), data, mload(data), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}