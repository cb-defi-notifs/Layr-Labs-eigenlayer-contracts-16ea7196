# Contract specs

## Depositing assets with EigenLayr
Any Ethereum account with ETH, who wants to participate in EigenLayr whether as a self-operator or as a delegator, needs to first interact with [EigenLayrDeposit contract](./EigenLayrDeposit.sol) in order to subject their ETH to additional slashing conditions from EigenLayer. Based on how that account wants to stake ETH with EigenLayer, there are multiple options:
  - enabling deposit of staking derivatives from liquid staking into EigenLayr while describing which     investment strategy to use for investing these staking derivatives,
  - enabling proving staking of ETH into settlement layer (beacon chain) before the launch of EigenLayr and then account it for staking into EigenLayr,
  - enabling depositing ETH into settlement layer via EigenLayr's withdrawal certificate and then then account it for staking into EigenLayr,
  - enabling acceptance of proof of staking into settlement layer, via depositor's own withdrawal certificate, in order to use it for staking into EigenLayr.
 
