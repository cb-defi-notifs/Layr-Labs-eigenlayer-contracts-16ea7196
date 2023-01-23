// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../src/contracts/interfaces/IInvestmentManager.sol";
import "../../src/contracts/interfaces/IInvestmentStrategy.sol";
import "../../src/contracts/interfaces/IEigenLayerDelegation.sol";
import "../../src/contracts/interfaces/IBLSRegistry.sol";
import "../../src/contracts/interfaces/IWhitelister.sol";
import "./Staker.sol";


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ERC20PresetMinterPauser.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";


contract Whitelister is IWhitelister, Ownable {
    //address constant investmentManager = 0x0000000000000000000000000000000000000000;
    //TODO: change before deploy
    IInvestmentManager immutable investmentManager;
    ERC20PresetMinterPauser immutable stakeToken;
    IInvestmentStrategy immutable stakeStrategy;
    IEigenLayerDelegation delegation;

    IBLSRegistry immutable registry;

    uint256 public constant DEFAULT_AMOUNT = 100e18;

    //TODO: Deploy ERC20PresetMinterPauser and a corresponding InvestmentStrategyBase for it
    //TODO: Transfer ownership of Whitelister to multisig after deployment
    //TODO: Give mint/admin/pauser permssions of whitelistToken to Whitelister and multisig after deployment
    //TODO: Give up mint/admin/pauser permssions of whitelistToken for deployer
    constructor(
        IInvestmentManager _investmentManager,
        IEigenLayerDelegation _delegation,
        ERC20PresetMinterPauser _token,
        IInvestmentStrategy _strategy,
        IBLSRegistry _registry
    ) {
        investmentManager = _investmentManager;
        delegation = _delegation;
        stakeToken = _token;
        stakeStrategy = _strategy;

        registry = _registry;
    }

    function whitelist(address operator) public onlyOwner {
        // mint the staker the tokens
        stakeToken.mint(getStaker(operator), DEFAULT_AMOUNT);
        // deploy the staker
        Create2.deploy(
            0,
            bytes32(uint256(uint160(operator))),
            abi.encodePacked(
                type(Staker).creationCode,
                abi.encode(
                    stakeStrategy,
                    investmentManager,
                    delegation,
                    stakeToken,
                    DEFAULT_AMOUNT,
                    operator
                )
            )
        );

        // add operator to whitelist
        address[] memory operators = new address[](1);
        operators[0] = operator;
        registry.addToWhitelist(operators);
    }

    function getStaker(address operator) public view returns (address) {
        return
            Create2.computeAddress(
                bytes32(uint256(uint160(operator))), //salt
                keccak256(
                    abi.encodePacked(
                        type(Staker).creationCode,
                        abi.encode(
                            stakeStrategy,
                            investmentManager,
                            delegation,
                            stakeToken,
                            DEFAULT_AMOUNT,
                            operator
                        )
                    )
                ) 
            );
    }

    function depositIntoStrategy(
        address staker,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount
    ) public onlyOwner returns (bytes memory) {
       
        bytes memory data = abi.encodeWithSelector(
                IInvestmentManager.depositIntoStrategy.selector,
                strategy,
                token,
                amount
        );

        return Staker(staker).callAddress(address(investmentManager), data);
    }

    function queueWithdrawal(
        address staker,
        uint256[] calldata strategyIndexes,
        IInvestmentManager.StratsTokensShares calldata sts,
        address withdrawer,
        bool undelegateIfPossible
    ) public onlyOwner returns (bytes memory) {
        bytes memory data = abi.encodeWithSelector(
                IInvestmentManager.queueWithdrawal.selector,
                strategyIndexes,
                sts,
                withdrawer,
                undelegateIfPossible
            );
        return Staker(staker).callAddress(address(investmentManager), data);
    }

    function completeQueuedWithdrawal(
        address staker,
        IInvestmentManager.QueuedWithdrawal calldata queuedWithdrawal,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) public onlyOwner returns (bytes memory) {
        bytes memory data = abi.encodeWithSelector(
                IInvestmentManager.completeQueuedWithdrawal.selector,
                queuedWithdrawal,
                middlewareTimesIndex,
                receiveAsTokens
        );

        return Staker(staker).callAddress(address(investmentManager), data);
    }

    function transfer(
        address staker,
        address token,
        address to,
        uint256 amount
    ) public onlyOwner returns (bytes memory) {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);

        return Staker(staker).callAddress(token, data);
    }

    function callAddress(
        address to,
        bytes memory data
    ) public onlyOwner payable returns (bytes memory) {
        (bool ok, bytes memory res) = payable(to).call{value: msg.value}(data);
        if (!ok) {
            revert(string(res));
        }
        return res;
    }
}