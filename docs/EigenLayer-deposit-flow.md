
# Deposit Flow

There are 2 main ways in which a staker can deposit new funds into EigenLayer -- depositing into an InvestmentStrategy through the InvestmentManager, and depositing "Beacon Chain ETH" (or proof thereof) through the EigenPodManager.

## Depositing Into an InvestmentStrategy Through the InvestmentManager
The InvestmentManger has two functions for depositing funds into InvestmentStrategy contracts -- `depositIntoStrategy` and `depositIntoStrategyOnBehalfOf`. In both cases, a specified `amount` of an ERC20 `token` is transferred from the caller to a specified InvestmentStrategy-type contract `strategy`. New shares in the strategy are created according to the return value of `strategy.deposit`; when calling `depositIntoStrategy` these shares are credited to the caller, whereas when calling `depositIntoStrategyOnBehalfOf` the new shares are credited to a specified `staker`, who must have also signed off on the deposit (this enables more complex, contract-mediated deposits, while a signature is required to mitigate the possibility of griefing or dusting-type attacks).
We note as well that deposits cannot be made to a 'frozen' address, i.e. to the address of an operator who has been slashed or to a staker who is actively delegated to a slashed operator.
When performing a deposit through the InvestmentManager, the flow of calls between contracts looks like the following:

![Depositing Into EigenLayer Through the InvestmentManager -- Contract Flow](images/EL_depositing.png?raw=true "Title")

1. The depositor makes the initial call to either `InvestmentManager.depositIntoStrategy` or `InvestmentManager.depositIntoStrategyOnBehalfOf`
2. The InvestmentManager calls `Slasher.isFrozen` to verifier that the recipient (either the caller or the specified `staker` input) is not 'frozen' on EigenLayer
3. The InvestmentManager calls the specified `token` contract, transferring specified `amount` of tokens from the caller to the specified `strategy`
4. The InvestmentManager calls `strategy.deposit`, and then credits the returned `shares` value to the recipient
5. The InvestmentManager calls `EigenLayerDelegation.increaseDelegatedShares` to ensure that -- if the recipient has delegated to an operator -- the operator's delegated share amounts are updated appropriately

## Depositing Beacon Chain ETH Through the EigenPodManager

<!-- TODO: write this section -->
