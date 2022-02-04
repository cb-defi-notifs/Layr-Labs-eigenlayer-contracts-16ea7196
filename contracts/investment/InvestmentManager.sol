// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.11;

import "../interfaces/InvestmentInterfaces.sol";

contract InvestmentManager is IInvestmentManager {
    mapping(IInvestmentStrategy => bool) public stratEverApproved;
    mapping(IInvestmentStrategy => bool) public stratApproved;
    mapping(address => mapping(IInvestmentStrategy => uint256)) public investorStratShares;
    mapping(address => IInvestmentStrategy[]) public investorStrats;
    address public entryExit;
    address public governer;

    constructor(address _entryExit, IInvestmentStrategy[] memory strategies) {
        entryExit = _entryExit;
        governer = msg.sender;
        for(uint i = 0; i < strategies.length; i++){
            stratApproved[strategies[i]] = true;
            if(!stratEverApproved[strategies[i]]) {
                stratEverApproved[strategies[i]] = true;
            }
        }
    }   

    function addInvestmentStrategies(IInvestmentStrategy[] calldata strategies) external {
        require(msg.sender == governer, "Only governer can add strategies");
        for(uint i = 0; i < strategies.length; i++){
            stratApproved[strategies[i]] = true;
            if(!stratEverApproved[strategies[i]]) {
                stratEverApproved[strategies[i]] = true;
            }
        }
    }

    function removeInvestmentStrategies(
        IInvestmentStrategy[] calldata strategies
    ) external {
        require(msg.sender == governer, "Only governer can add strategies");   
        for(uint i = 0; i < strategies.length; i++){
            stratApproved[strategies[i]] = false;
        }  
    }

    function depositIntoStrategies(
        address depositer,
        IInvestmentStrategy[] calldata strategies,
        IERC20[][] calldata tokens,
        uint256[][] calldata amounts
    ) external returns (uint256[] memory) {
        require(msg.sender == entryExit, "Only governer can add strategies");
        uint256[] memory shares = new uint256[](strategies.length);
        for(uint i = 0; i < strategies.length; i++){
            require(stratApproved[strategies[i]], "Can only deposit from approved strategies");
            shares[i] = strategies[i].deposit(depositer, tokens[i], amounts[i]);
            investorStratShares[depositer][strategies[i]] += shares[i];
        }  
        return shares;
    }

    function withdrawFromStrategies(
        address depositer,
        IInvestmentStrategy[] calldata strategies,
        IERC20[][] calldata tokens,
        uint256[][] calldata amounts
    ) external {
        require(msg.sender == entryExit, "Only governer can add strategies");
        uint256[] memory shares = new uint256[](strategies.length);
        for(uint i = 0; i < strategies.length; i++){
            require(stratApproved[strategies[i]], "Can only deposit from approved strategies");
            investorStratShares[depositer][strategies[i]] -= strategies[i].withdraw(msg.sender, tokens[i], amounts[i]);
        }  
    }

    function getStrategyShares(address depositer, IInvestmentStrategy[] calldata strategies)
        external
        returns (uint256[] memory) {
            uint256[] memory shares = new uint256[](strategies.length);
            for(uint i = 0; i < strategies.length; i++){
                shares[i] = investorStratShares[depositer][strategies[i]];
            }
            return shares;
        }
}