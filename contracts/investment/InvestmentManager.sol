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
    mapping(address => uint256) public eigenDeposited;
    uint256 public totalConsensusLayerEthStaked;
    uint256 public totalEigenStaked;
    address public entryExit;
    address public governor;
    address public slasher;
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; //placeholder address for native asset

    // adds the given strategies to the investment manager
    constructor(address _entryExit, IInvestmentStrategy[] memory strategies, address _slasher) {
        entryExit = _entryExit;
        governor = msg.sender;
        slasher = _slasher;
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
        require(msg.sender == governor, "Only governor can add strategies");
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
        require(msg.sender == governor, "Only governor can add strategies");
        for (uint256 i = 0; i < strategies.length; i++) {
            stratApproved[strategies[i]] = false;
        }
    }

    // deposits given tokens and amounts into the given strategies on behalf of depositor
    function depositIntoStrategy(
        address depositor,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount
    ) external payable returns (uint256 shares) {
        require(msg.sender == entryExit, "Only governor can add strategies");
        shares = _depositIntoStrategy(depositor, strategy, token, amount);
    }

    // deposits given tokens and amounts into the given strategies on behalf of depositor
    function depositIntoStrategies(
        address depositor,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external payable returns (uint256[] memory) {
        require(msg.sender == entryExit, "Only governor can add strategies");
        uint256[] memory shares = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            shares[i] = _depositIntoStrategy(depositor, strategies[i], tokens[i], amounts[i]);
        }
        return shares;
    }

    function _depositIntoStrategy(
        address depositor,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount
    ) internal returns (uint256 shares) {
        require(
            stratApproved[strategy],
            "Can only deposit from approved strategies"
        );
        // if they dont have existing shares of this strategy, add it to their strats
        if (investorStratShares[depositor][strategy] == 0) {
            investorStrats[depositor].push(strategy);
        }
        //transfer tokens to the strategy
        _transferTokenOrEth(token, depositor, address(strategy), amount);
        shares = strategy.deposit(
            token,
            amount
        );
        // add the returned shares to their existing shares for this strategy
        investorStratShares[depositor][strategy] += shares;
    }

    // withdraws the given tokens and shareAmounts from the given strategies on behalf of the depositor
    function withdrawFromStrategies(
        address depositor,
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts
    ) external {
        require(msg.sender == entryExit, "Only governor can add strategies");
        uint256 strategyIndexIndex;
        for (uint256 i = 0; i < strategies.length; i++) {
            require(
                stratEverApproved[strategies[i]],
                "Can only withdraw from approved strategies"
            );
            // subtract the returned shares to their existing shares for this strategy
            investorStratShares[depositor][strategies[i]] -= strategies[i]
                .withdraw(depositor, tokens[i], shareAmounts[i]);
            // if no existing shares, remove is from this investors strats
            if (investorStratShares[depositor][strategies[i]] == 0) {
                require(
                    investorStrats[depositor][
                        strategyIndexes[strategyIndexIndex]
                    ] == strategies[i],
                    "Strategy index is incorrect"
                );
                // move the last element to the removed strategy's index, then shorten the array
                investorStrats[depositor][
                    strategyIndexes[strategyIndexIndex]
                ] = investorStrats[depositor][
                    investorStrats[depositor].length - 1
                ];
                investorStrats[depositor].pop();
                strategyIndexIndex++;
            }
        }
    }

    // withdraws the given token and shareAmount from the given strategy on behalf of the depositor
    function withdrawFromStrategy(
        address depositor,
        uint256 strategyIndex,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 shareAmount
    ) external {
        require(msg.sender == entryExit, "Only governor can add strategies");
        require(
            stratEverApproved[strategy],
            "Can only withdraw from approved strategies"
        );
        // subtract the returned shares to their existing shares for this strategy
        investorStratShares[depositor][strategy] -= strategy
            .withdraw(depositor, token, shareAmount);
        // if no existing shares, remove is from this investors strats
        if (investorStratShares[depositor][strategy] == 0) {
            require(
                investorStrats[depositor][
                    strategyIndex
                ] == strategy,
                "Strategy index is incorrect"
            );
            // move the last element to the removed strategy's index, then shorten the array
            investorStrats[depositor][
                strategyIndex
            ] = investorStrats[depositor][
                investorStrats[depositor].length - 1
            ];
            investorStrats[depositor].pop();
        }
    }

    function slashShares(
        address slashed,
        address recipient,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata strategyIndexes,
        uint256[] calldata shareAmounts,
        uint256 maxSlashedAmount
    ) external {
        require(msg.sender == slasher, "Only Slasher");
        uint256 strategyIndexIndex;
        uint256 slashedAmount;
        for (uint256 i = 0; i < strategies.length; i++) {
            require(
                stratEverApproved[strategies[i]],
                "Can only withdraw from approved strategies"
            );
            slashedAmount += strategies[i].underlyingEthValueOfShares(shareAmounts[i]);
            // subtract the shares for this strategy
            investorStratShares[slashed][strategies[i]] -= shareAmounts[i];
            // if no existing shares, remove is from this investors strats
            if (investorStratShares[slashed][strategies[i]] == 0) {
                require(
                    investorStrats[slashed][
                        strategyIndexes[strategyIndexIndex]
                    ] == strategies[i],
                    "Strategy index is incorrect"
                );
                // move the last element to the removed strategy's index, then shorten the array
                investorStrats[slashed][
                    strategyIndexes[strategyIndexIndex]
                ] = investorStrats[slashed][
                    investorStrats[slashed].length - 1
                ];
                investorStrats[slashed].pop();
                strategyIndexIndex++;
            }
            if (investorStratShares[recipient][strategies[i]] == 0) {
                investorStrats[recipient].push(strategies[i]);
            }
            investorStratShares[recipient][strategies[i]] += shareAmounts[i];
        }
        require(slashedAmount <= maxSlashedAmount, "excessive slashing");
    }

    // sets a user's eth balance on the consesnsus layer
    function depositConsenusLayerEth(address depositor, uint256 amount)
        external
        returns (uint256)
    {
        require(msg.sender == entryExit, "Only governor can add strategies");
        totalConsensusLayerEthStaked =
            totalConsensusLayerEthStaked +
            amount -
            consensusLayerEth[depositor];
        consensusLayerEth[depositor] = amount;
        return amount;
    }

    // sets a user's eigen deposit
    function depositEigen(address depositor, uint256 amount)
        external
        returns (uint256)
    {
        require(msg.sender == entryExit, "Only governor can add strategies");
        totalEigenStaked =
            totalEigenStaked +
            amount -
            eigenDeposited[depositor];
        eigenDeposited[depositor] = amount;
        return amount;
    }

    // gets depositor's shares in the given strategies
    function getStrategies(address depositor)
        external
        view
        returns (IInvestmentStrategy[] memory)
    {
        return investorStrats[depositor];
    }

    // gets depositor's shares in the given strategies
    function getStrategyShares(address depositor)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory shares = new uint256[](investorStrats[depositor].length);
        for (uint256 i = 0; i < shares.length; i++) {
            shares[i] = investorStratShares[depositor][investorStrats[depositor][i]];
        }
        return shares;
    }

    // gets depositor's eth deposited directly to consensus layer
    function getConsensusLayerEth(address depositor)
        external
        view
        returns (uint256)
    {
        return consensusLayerEth[depositor];
    }

    // gets depositor's eige deposited
    function getEigen(address depositor)
        external
        view
        returns (uint256)
    {
        return eigenDeposited[depositor];
    }

    // gets depositor's shares in the given strategies
    function getDeposits(address depositor)
        external
        view
        returns (IInvestmentStrategy[] memory, uint256[] memory, uint256, uint256)
    {
        uint256[] memory shares = new uint256[](investorStrats[depositor].length);
        for (uint256 i = 0; i < shares.length; i++) {
            shares[i] = investorStratShares[depositor][investorStrats[depositor][i]];
        }
        return (investorStrats[depositor], shares, consensusLayerEth[depositor], eigenDeposited[depositor]);
    }

    // gets depositor's eth value staked
    function getUnderlyingEthStaked(address depositer)
        external
        returns (uint256)
    {
        uint256 stake = consensusLayerEth[depositer];
        uint256 numStrats = investorStrats[depositer].length;
        // for all strats find uderlying eth value of shares
        for (uint256 i = 0; i < numStrats; i++) {
            IInvestmentStrategy strat = investorStrats[depositer][i];
            stake += strat.underlyingEthValueOfShares(investorStratShares[depositer][strat]);
        }
        return stake;
    }

    // gets depositor's eth value staked
    function getUnderlyingEthStakedView(address depositer)
        external
        view
        returns (uint256)
    {
        uint256 stake = consensusLayerEth[depositer];
        uint256 numStrats = investorStrats[depositer].length;
        // for all strats find uderlying eth value of shares
        for (uint256 i = 0; i < numStrats; i++) {
            IInvestmentStrategy strat = investorStrats[depositer][i];
            stake += strat.underlyingEthValueOfSharesView(investorStratShares[depositer][strat]);
        }
        return stake;
    }

    function _transferTokenOrEth(IERC20 token, address sender, address receiver, uint256 amount) internal {
        if (address(token) == ETH) {
            (bool success, ) = receiver.call{value: amount}("");
            require(success, "failed to transfer value");
        } else {
            token.transferFrom(sender, receiver, amount);
        }
    }
}
