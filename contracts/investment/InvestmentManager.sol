// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/InvestmentInterfaces.sol";

contract InvestmentManager is IInvestmentManager {
    mapping(IInvestmentStrategy => bool) public stratEverApproved;
    mapping(IInvestmentStrategy => bool) public stratApproved;
    // staker => InvestmentStrategy => num shares
    mapping(address => mapping(IInvestmentStrategy => uint256))
        public investorStratShares;
    mapping(address => IInvestmentStrategy[]) public investorStrats;
    mapping(address => uint256) public consensusLayerEth;
    uint256 public totalConsensusLayerEth;
    address public entryExit;
    address public governer;

    // adds the given strategies to the investment manager
    constructor(address _entryExit, IInvestmentStrategy[] memory strategies) {
        entryExit = _entryExit;
        governer = msg.sender;
        for (uint256 i = 0; i < strategies.length; i++) {
            stratApproved[strategies[i]] = true;
            if (!stratEverApproved[strategies[i]]) {
                stratEverApproved[strategies[i]] = true;
            }
        }
    }

    // adds the given strategies to the investment manager
    function addInvestmentStrategies(IInvestmentStrategy[] calldata strategies)
        external
    {
        require(msg.sender == governer, "Only governer can add strategies");
        for (uint256 i = 0; i < strategies.length; i++) {
            stratApproved[strategies[i]] = true;
            if (!stratEverApproved[strategies[i]]) {
                stratEverApproved[strategies[i]] = true;
            }
        }
    }

    // removes the given strategies from the investment manager
    function removeInvestmentStrategies(
        IInvestmentStrategy[] calldata strategies
    ) external {
        require(msg.sender == governer, "Only governer can add strategies");
        for (uint256 i = 0; i < strategies.length; i++) {
            stratApproved[strategies[i]] = false;
        }
    }

    // deposits given tokens and amounts into the given strategies on behalf of depositer
    function depositIntoStrategy(
        address depositer,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount
    ) external returns (uint256) {
        require(msg.sender == entryExit, "Only governer can add strategies");
        require(
            stratApproved[strategy],
            "Can only deposit from approved strategies"
        );
        // if they dont have existing shares of this strategy, add it to their strats
        if (investorStratShares[depositer][strategy] == 0) {
            investorStrats[depositer].push(strategy);
        }
        // add the returned shares to their existing shares for this strategy
        investorStratShares[depositer][strategy] += strategy.depositSingle(
            depositer,
            token,
            amount
        );
        return 0;
    }

    // deposits given tokens and amounts into the given strategies on behalf of depositer
    function depositIntoStrategies(
        address depositer,
        IInvestmentStrategy[] calldata strategies,
        IERC20[][] calldata tokens,
        uint256[][] calldata amounts
    ) external returns (uint256[] memory) {
        require(msg.sender == entryExit, "Only governer can add strategies");
        uint256[] memory shares = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            require(
                stratApproved[strategies[i]],
                "Can only deposit from approved strategies"
            );
            // if they dont have existing shares of this strategy, add it to their strats
            if (investorStratShares[depositer][strategies[i]] == 0) {
                investorStrats[depositer].push(strategies[i]);
            }
            // add the returned shares to their existing shares for this strategy
            shares[i] = strategies[i].deposit(depositer, tokens[i], amounts[i]);
            investorStratShares[depositer][strategies[i]] += shares[i];
        }
        return shares;
    }

    // withdraws the given tokens and amounts from the given strategies on behalf of the depositer
    function withdrawFromStrategies(
        address depositer,
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[][] calldata tokens,
        uint256[][] calldata amounts
    ) external {
        require(msg.sender == entryExit, "Only governer can add strategies");
        uint256 strategyIndexIndex = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            require(
                stratEverApproved[strategies[i]],
                "Can only deposit from approved strategies"
            );
            // subtract the returned shares to their existing shares for this strategy
            investorStratShares[depositer][strategies[i]] -= strategies[i]
                .withdraw(msg.sender, tokens[i], amounts[i]);
            // if no existing shares, remove is from this investors strats
            if (investorStratShares[depositer][strategies[i]] == 0) {
                require(
                    investorStrats[depositer][
                        strategyIndexes[strategyIndexIndex]
                    ] == strategies[i],
                    "Strategy index is incorrect"
                );
                // move the last element to the removed strategy's index, then shorten the array
                investorStrats[depositer][
                    strategyIndexes[strategyIndexIndex]
                ] = investorStrats[depositer][
                    investorStrats[depositer].length - 1
                ];
                investorStrats[depositer].pop();
                strategyIndexIndex++;
            }
        }
    }

    // sets a users eth balance on the consesnsus layer
    function depositConsenusLayerEth(address depositer, uint256 amount)
        external
        returns (uint256)
    {
        require(msg.sender == entryExit, "Only governer can add strategies");
        consensusLayerEth[depositer] = amount;
        totalConsensusLayerEth =
            totalConsensusLayerEth +
            amount -
            consensusLayerEth[depositer];
        return amount;
    }

    // gets deposters shares in the given strategies
    function getStrategies(address depositer)
        external
        view
        returns (IInvestmentStrategy[] memory)
    {
        return investorStrats[depositer];
    }

    // gets deposters shares in the given strategies
    function getStrategyShares(address depositer)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory shares = new uint256[](investorStrats[depositer].length);
        for (uint256 i = 0; i < shares.length; i++) {
            shares[i] = investorStratShares[depositer][investorStrats[depositer][i]];
        }
        return shares;
    }

    // gets deposters eth deposited directly to consensus layer
    function getConsensusLayerEth(address depositer)
        external
        view
        returns (uint256)
    {
        return consensusLayerEth[depositer];
    }
}
