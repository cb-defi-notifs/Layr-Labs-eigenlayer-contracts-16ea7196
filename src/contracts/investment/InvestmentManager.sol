// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IInvestmentManager.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "../utils/Governed.sol";
import "../utils/Initializable.sol";
import "./storage/InvestmentManagerStorage.sol";

// TODO: withdrawals of Eigen (and consensus layer ETH?)
/**
 * @notice This contract is for managing investments in different strategies. The main 
 *         functionalities are:
 *            - adding and removing investment strategies that any delegator can invest into
 *            - enabling deposit of assets into specified investment strategy(s)
 *            - enabling removal of assets from specified investment strategy(s)
 *            - recording deposit of ETH into settlement layer
 *            - recording deposit of Eigen for securing EigenLayr
 *            - slashing of assets for permissioned strategies          
 */
contract InvestmentManager is
    Initializable,
    Governed,
    InvestmentManagerStorage
{
    IERC1155 public immutable EIGEN;
    IEigenLayrDelegation public immutable delegation;

    modifier onlyNotDelegated() {
        require(
            delegation.isNotDelegated(msg.sender),
            "cannot withdraw while delegated"
        );
        _;
    }

    constructor(IERC1155 _EIGEN, IEigenLayrDelegation _delegation) {
        EIGEN = _EIGEN;
        delegation = _delegation;
    }

    /**
     * @notice Initializes the investment manager contract with a given set of strategies 
     *         and slashing rules. 
     */
    /**
     * @param strategies are the initial set of strategies
     * @param _slasher is the set of slashing rules to be used for the strategies associated with 
     *        this investment manager contract   
     */
    function initialize(
        IInvestmentStrategy[] memory strategies,
        address _slasher
    ) external initializer {
        // make the sender who is initializing the investment manager as the governor
        _transferGovernor(msg.sender);

        slasher = _slasher;

        // record the strategies as approved
        for (uint256 i = 0; i < strategies.length; i++) {
            stratApproved[strategies[i]] = true;
            if (!stratEverApproved[strategies[i]]) {
                stratEverApproved[strategies[i]] = true;
            }
        }
    }



    /**
     * @notice used for adding new investment strategies to the list of approved stratgeies
     *         of the investment manager contract 
     */ 
    /**
     * @param strategies are new strategies to be added
     */
    /**
     * @dev only the governor can add new strategies
     */ 
    function addInvestmentStrategies(IInvestmentStrategy[] calldata strategies)
        external
        onlyGovernor
    {
        for (uint256 i = 0; i < strategies.length; i++) { 
            stratApproved[strategies[i]] = true;

            if (!stratEverApproved[strategies[i]]) {
                stratEverApproved[strategies[i]] = true;
            }
        }
    }



    /**
     * @notice used for removing investment strategies from the list of approved stratgeies
     *         of the investment manager contract 
     */ 
    /**
     * @param strategies are strategies to be removed
     */
    /**
     * @dev only the governor can add new strategies
     */ 
    function removeInvestmentStrategies(
        IInvestmentStrategy[] calldata strategies
    ) external onlyGovernor {
        // set the approval status to false
        for (uint256 i = 0; i < strategies.length; i++) {
            stratApproved[strategies[i]] = false;
        }
    }



    /**
     * @notice used for investing a depositor's asset into the specified strategy in the 
     *         behalf of the depositor 
     */
    /**
     * @param depositor is the address of the user who is investing assets into specified strategy,
     * @param strategy is the specified strategy where investment is to be made, 
     * @param token is the denomination in which the investment is to be made,
     * @param amount is the amount of token to be invested in the strategy by the depositor
     */
    /**
     * @dev this function is called when a user stakes ETH for the purpose of depositing
     *      into liquid staking first, use the associated liquid stake token for providing 
     *      validation service to EigenLayr and invest the token in DeFi. For more details, 
     *      see EigenLayrDeposit.sol.    
     */ 
    function depositIntoStrategy(
        address depositor,
        IInvestmentStrategy strategy,
        IERC20 token,
        uint256 amount
    ) external payable onlyGovernor returns (uint256 shares) {
        shares = _depositIntoStrategy(depositor, strategy, token, amount);
    }



    /**
     * @notice used for investing a depositor's assets into multiple specified strategy, in the 
     *         behalf of the depositor, with each of the investment being done in terms of a
     *         specified token and their respective amount. 
     */
    function depositIntoStrategies(
        address depositor,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata amounts
    ) external payable onlyGovernor returns (uint256[] memory) {
        uint256[] memory shares = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            shares[i] = _depositIntoStrategy(
                depositor,
                strategies[i],
                tokens[i],
                amounts[i]
            );
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

        // transfer tokens from the depositor to the strategy
        _transferTokenOrEth(token, depositor, address(strategy), amount);

        // deposit the assets into the specified strategy and get the equivalent amount of
        // shares in that strategy
        shares = strategy.deposit(token, amount);

        // add the returned shares to their existing shares for this strategy
        investorStratShares[depositor][strategy] += shares;
    }



    /**
     * @notice Used to withdraw the given token and shareAmount from the given strategies. 
     */
    /**
     * @dev Only those stakers who have notified the system that they want to undelegate 
     *      from the system, via calling commitUndelegation in EigenLayrDelegation.sol, can
     *      call this function.
     */
    function withdrawFromStrategies(
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shareAmounts
    ) external onlyNotDelegated {
        uint256 strategyIndexIndex;
        address depositor = msg.sender;

        uint256 strategiesLength = strategies.length;
        for (uint256 i = 0; i < strategiesLength;) {
            require(
                stratEverApproved[strategies[i]],
                "Can only withdraw from approved strategies"
            );
            // subtract the shares from the depositor's existing shares for this strategy
            investorStratShares[depositor][strategies[i]] -= shareAmounts[i];

            // if no existing shares, remove this from this investors strats
            if (investorStratShares[depositor][strategies[i]] == 0) {
                // if the strategy matches with the strategy index provided
                if (
                    investorStrats[depositor][
                        strategyIndexes[strategyIndexIndex]
                    ] == strategies[i]
                ) {
                    // replace the strategy with the last strategy in the list
                    investorStrats[depositor][
                        strategyIndexes[strategyIndexIndex]
                    ] = investorStrats[depositor][
                        investorStrats[depositor].length - 1
                    ];
                } else {
                    //loop through all of the strategies, find the right one, then replace
                    uint256 stratsLength = investorStrats[depositor].length;

                    for (uint256 j = 0; j < stratsLength; ) {
                        if (investorStrats[depositor][j] == strategies[i]) {

                            //replace the strategy with the last strategy in the list
                            investorStrats[depositor][j] = investorStrats[
                                depositor
                            ][investorStrats[depositor].length - 1];
                            break;
                        }
                        unchecked {
                            ++j;
                        }
                    }
                }
                investorStrats[depositor].pop();
                strategyIndexIndex++;
            }

            // tell the strategy to send the appropriate amount of funds to the depositor
            strategies[i].withdraw(depositor, tokens[i], shareAmounts[i]);

            //increment the loop
            unchecked {
                ++i;
            }
        }
    }


    /**
     * @notice Used to withdraw the given token and shareAmount from the given strategy. 
     */
    /**
     * @dev Only those stakers who have notified the system that they want to undelegate 
     *      from the system, via calling commitUndelegation in EigenLayrDelegation.sol, can
     *      call this function.
     */
    // CRITIC: (1) transfer of funds happening before update to the depositor's share,
    //             possibility of draining away all fund - re-entry bug
    //         (2) a staker can get its asset back before finalizeUndelegation. Therefore, 
    //             what is the incentive for calling finalizeUndelegation and starting off
    //             the challenge period when the staker can get its asset back before
    //             fulfilling its obligations. More details in slack.   
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
        // subtract the shares from the depositor's existing shares for this strategy
        investorStratShares[depositor][strategy] -= shareAmount;
        // if no existing shares, remove is from this investors strats
        if (investorStratShares[depositor][strategy] == 0) {
            require(
                investorStrats[depositor][strategyIndex] == strategy,
                "Strategy index is incorrect"
            );
            // move the last element to the removed strategy's index, then shorten the array
            investorStrats[depositor][strategyIndex] = investorStrats[
                depositor
            ][investorStrats[depositor].length - 1];
            investorStrats[depositor].pop();
        }
        // tell the strategy to send the appropriate amount of funds to the depositor
        strategy.withdraw(
            depositor,
            token,
            shareAmount
        );
    }



    /**
     * @notice Used for slashing a certain user and transferring the slashed assets to
     *         the a certain recipient. 
     */
    /**
     * @dev only Slasher contract can call this function and slashing can be done only for 
     *      investment strategies that have permitted the Slasher contract to do slashing.
     *      More details on that in Slasher.sol.
     */ 
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
            slashedAmount += strategies[i].underlyingEthValueOfShares(
                shareAmounts[i]
            );

            // subtract the shares for this strategy from that of slashed
            investorStratShares[slashed][strategies[i]] -= shareAmounts[i];

            // if no existing shares, remove this from slashed's investor strats
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
                ] = investorStrats[slashed][investorStrats[slashed].length - 1];
                investorStrats[slashed].pop();
                strategyIndexIndex++;
            }

            // add investor strats to that of recipient if it has not invested in this strategy yet
            if (investorStratShares[recipient][strategies[i]] == 0) {
                investorStrats[recipient].push(strategies[i]);
            }

            // add the slashed shares to that of the recipient
            investorStratShares[recipient][strategies[i]] += shareAmounts[i];
        }

        require(slashedAmount <= maxSlashedAmount, "excessive slashing");
    }


    /**
     * @notice Used for setting the delegator's new ETH balance in the settlement layer
     */
    /**
     * @dev Caution that @param amount is the new ETH balance that the @param depositor wants
     *      and not the increment to the new balance.
     */ 
    function depositConsenusLayerEth(address depositor, uint256 amount)
        external
        onlyGovernor
        returns (uint256)
    {
        // updating the total ETH staked into the settlement layer
        totalConsensusLayerEthStaked =
            totalConsensusLayerEthStaked +
            amount -
            consensusLayerEth[depositor];

        // record the ETH that has been staked by the depositor    
        consensusLayerEth[depositor] = amount;

        return amount;
    }

    // sets a user's eigen deposit
    /**
     * @notice Used for setting the delegator's new Eigen balance
     */
    /**
     * @dev Caution that @param amount is the new Eigen balance that the @param depositor wants
     *      and not the increment to the new balance.
     */ 
    function depositEigen(address depositor, uint256 amount)
        external
        onlyGovernor
        returns (uint256)
    {
        totalEigenStaked =
            totalEigenStaked +
            amount -
            eigenDeposited[depositor];

        eigenDeposited[depositor] = amount;

        return amount;
    }

    /**
     * @notice gets depositor's strategies
     */
    function getStrategies(address depositor)
        external
        view
        returns (IInvestmentStrategy[] memory)
    {
        return investorStrats[depositor];
    }

    /**
     * @notice gets depositor's shares in its strategies
     */
    function getStrategyShares(address depositor)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory shares = new uint256[](
            investorStrats[depositor].length
        );

        for (uint256 i = 0; i < shares.length; i++) {
            shares[i] = investorStratShares[depositor][
                investorStrats[depositor][i]
            ];
        }

        return shares;
    }

    
    /**
     * @notice gets depositor's ETH that has been deposited directly to settlement layer
     */
    function getConsensusLayerEth(address depositor)
        external
        view
        returns (uint256)
    {
        return consensusLayerEth[depositor];
    }


    /**
     * @notice gets depositor's Eigen that has been deposited
     */
    function getEigen(address depositor) external view returns (uint256) {
        return eigenDeposited[depositor];
    }


    /**
     * @notice get all details on the depositor's investments, shares, ETH and Eigen staked.
     */
    /**
     * @return (depositor's strategies, shares in these strategies, ETH staked, Eigen staked)
     */
    function getDeposits(address depositor)
        external
        view
        returns (
            IInvestmentStrategy[] memory,
            uint256[] memory,
            uint256,
            uint256
        )
    {
        uint256[] memory shares = new uint256[](
            investorStrats[depositor].length
        );
        for (uint256 i = 0; i < shares.length; i++) {
            shares[i] = investorStratShares[depositor][
                investorStrats[depositor][i]
            ];
        }
        return (
            investorStrats[depositor],
            shares,
            consensusLayerEth[depositor],
            eigenDeposited[depositor]
        );
    }


    /**
     * @notice get underlying sum of actual ETH staked into settlement layer and 
     *         and the ETH-denominated value of shares in various investment strategies 
     *         for the given depositor    
     */
    function getUnderlyingEthStaked(address depositor)
        external
        returns (uint256)
    {
        // actual ETH staked in settlement layer
        uint256 stake = consensusLayerEth[depositor];

        // for all strats find uderlying eth value of shares
        uint256 numStrats = investorStrats[depositor].length;
        for (uint256 i = 0; i < numStrats; i++) {
            IInvestmentStrategy strat = investorStrats[depositor][i];
            stake += strat.underlyingEthValueOfShares(
                investorStratShares[depositor][strat]
            );
        }

        return stake;
    }

    function getUnderlyingEthStakedView(address depositor)
        external
        view
        returns (uint256)
    {
        uint256 stake = consensusLayerEth[depositor];
        uint256 numStrats = investorStrats[depositor].length;
        // for all strats find uderlying eth value of shares
        for (uint256 i = 0; i < numStrats; i++) {
            IInvestmentStrategy strat = investorStrats[depositor][i];
            stake += strat.underlyingEthValueOfSharesView(
                investorStratShares[depositor][strat]
            );
        }
        return stake;
    }

    /**
     * @notice get the ETH-denominated value of shares in specified investment strategies 
     */
    function getUnderlyingEthOfStrategyShares(
        IInvestmentStrategy[] calldata strats,
        uint256[] calldata shares
    ) external returns (uint256) {
        uint256 stake;
        uint256 numStrats = strats.length;
        require(
            numStrats == shares.length,
            "shares and strats must be same length"
        );

        // for all strats find uderlying eth value of shares
        for (uint256 i = 0; i < numStrats; i++) {
            stake += strats[i].underlyingEthValueOfShares(shares[i]);
        }
        return stake;
    }



    function getUnderlyingEthOfStrategySharesView(
        IInvestmentStrategy[] calldata strats,
        uint256[] calldata shares
    ) external view returns (uint256) {
        uint256 stake;
        uint256 numStrats = strats.length;
        require(
            numStrats == shares.length,
            "shares and strats must be same length"
        );
        // for all strats find uderlying eth value of shares
        for (uint256 i = 0; i < numStrats; i++) {
            stake += strats[i].underlyingEthValueOfSharesView(shares[i]);
        }
        return stake;
    }

    

    /**
     * @notice used for transferring specified amount of specified token from the 
     *         sender to the receiver
     */
    function _transferTokenOrEth(
        IERC20 token,
        address sender,
        address receiver,
        uint256 amount
    ) internal {
        if (address(token) == ETH) {
            (bool success, ) = receiver.call{value: amount}("");
            require(success, "failed to transfer value");
        } else {
            token.transferFrom(sender, receiver, amount);
        }
    }
}
