// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IERC1155.sol";
import "../utils/Governed.sol";
import "../utils/Initializable.sol";
import "./storage/InvestmentManagerStorage.sol";

// TODO: withdrawals of Eigen (and consensus layer ETH?)
contract InvestmentManager is Initializable, Governed, InvestmentManagerStorage {
    IERC1155 public immutable EIGEN;
    IEigenLayrDelegation public immutable delegation;

    modifier onlyNotDelegated() {
        require(delegation.isNotDelegated(msg.sender), "cannot withdraw while delegated");
        _;
    }

    constructor(IERC1155 _EIGEN, IEigenLayrDelegation _delegation) {
        EIGEN = _EIGEN;
        delegation = _delegation;
    }

    // adds the given strategies to the investment manager
    function initialize (IInvestmentStrategy[] memory strategies, address _slasher
    ) initializer external {
        _transferGovernor(msg.sender);
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
        external onlyGovernor
    {
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
    ) external onlyGovernor 
    {
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
    ) external payable onlyGovernor returns (uint256 shares) {
        shares = _depositIntoStrategy(depositor, strategy, token, amount);
    }

    // deposits given tokens and amounts into the given strategies on behalf of depositor
    function depositIntoStrategies(
        address depositor,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external payable onlyGovernor returns (uint256[] memory) {
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
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts
    ) external onlyNotDelegated {
        uint256 strategyIndexIndex;
        address depositor = msg.sender;
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
        uint256 strategyIndex,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 shareAmount
    ) external onlyNotDelegated {
        address depositor = msg.sender;
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
        external onlyGovernor
        returns (uint256)
    {
        totalConsensusLayerEthStaked =
            totalConsensusLayerEthStaked +
            amount -
            consensusLayerEth[depositor];
        consensusLayerEth[depositor] = amount;
        return amount;
    }

    // sets a user's eigen deposit
    function depositEigen(address depositor, uint256 amount)
        external onlyGovernor
        returns (uint256)
    {
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

    function getUnderlyingEthOfStrategyShares(IInvestmentStrategy[] calldata strats, uint256[] calldata shares)
        external
        returns (uint256)
    {
        uint256 stake;
        uint256 numStrats = strats.length;
        require(numStrats == shares.length, "shares and strats must be same length");
        // for all strats find uderlying eth value of shares
        for (uint256 i = 0; i < numStrats; i++) {
            stake += strats[i].underlyingEthValueOfShares(shares[i]);
        }
        return stake;
    }

    function getUnderlyingEthOfStrategySharesView(IInvestmentStrategy[] calldata strats, uint256[] calldata shares)
        external
        view
        returns (uint256)
    {
        uint256 stake;
        uint256 numStrats = strats.length;
        require(numStrats == shares.length, "shares and strats must be same length");
        // for all strats find uderlying eth value of shares
        for (uint256 i = 0; i < numStrats; i++) {
            stake += strats[i].underlyingEthValueOfSharesView(shares[i]);
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