# Solidity API

## Governor

### Proposal

```solidity
struct Proposal {
  uint256 id;
  address proposer;
  uint256 eta;
  address[] targets;
  uint256[] values;
  string[] signatures;
  bytes[] calldatas;
  uint256 startTime;
  uint256 endTime;
  uint256 forVotesFirstQuorum;
  uint256 againstVotesFirstQuorum;
  uint256 forVotesSecondQuorum;
  uint256 againstVotesSecondQuorum;
  bool canceled;
  bool executed;
}
```

### Receipt

```solidity
struct Receipt {
  bool hasVoted;
  bool support;
  uint96 firstQuorumVotes;
  uint96 secondQuorumVotes;
}
```

### ProposalState

```solidity
enum ProposalState {
  Pending,
  Active,
  Canceled,
  Defeated,
  Succeeded,
  Queued,
  Expired,
  Executed
}
```

### timelock

```solidity
contract Timelock timelock
```

The address of the Protocol Timelock

### proposalMaxOperations

```solidity
uint16 proposalMaxOperations
```

The maximum number of actions that can be included in a proposal

### votingDelay

```solidity
uint256 votingDelay
```

The delay before voting on a proposal may take place, once proposed. stored as uint256 in number of seconds

### votingPeriod

```solidity
uint256 votingPeriod
```

The duration of voting on a proposal, in seconds

### DOMAIN_TYPEHASH

```solidity
bytes32 DOMAIN_TYPEHASH
```

The EIP-712 typehash for the contract's domain

### BALLOT_TYPEHASH

```solidity
bytes32 BALLOT_TYPEHASH
```

The EIP-712 typehash for the ballot struct used by the contract

### VOTE_WEIGHTER

```solidity
contract IVoteWeigher VOTE_WEIGHTER
```

### REGISTRY

```solidity
contract IQuorumRegistry REGISTRY
```

### firstQuorumPercentage

```solidity
uint16 firstQuorumPercentage
```

The percentage of eth needed in support of a proposal required in order for a quorum
to be reached for the eth and for a vote to succeed, if an eigen quorum is also reached

### secondQuorumPercentage

```solidity
uint16 secondQuorumPercentage
```

The percentage of eigen needed in support of a proposal required in order for a quorum
to be reached for the eigen and for a vote to succeed, if an eth quorum is also reached

### proposalThresholdFirstQuorumPercentage

```solidity
uint16 proposalThresholdFirstQuorumPercentage
```

The percentage of eth required in order for a voter to become a proposer

### proposalThresholdSecondQuorumPercentage

```solidity
uint16 proposalThresholdSecondQuorumPercentage
```

The percentage of eigen required in order for a voter to become a proposer

### proposalCount

```solidity
uint256 proposalCount
```

The total number of proposals

### multisig

```solidity
address multisig
```

Address of multisig or other trusted party. Has zero extra votes, but can make proposals without meeting proposal
        thresholds, and that pass by default
        In other words, proposals created by the 'multsig' address require at least a quorum to reject them in order to
        *not* pass, but otherwise operate like normal proposals, where the side with most votes wins

### receipts

```solidity
mapping(uint256 => mapping(address => struct Governor.Receipt)) receipts
```

Receipts of ballots for the entire set of voters

### proposals

```solidity
mapping(uint256 => struct Governor.Proposal) proposals
```

The official record of all proposals ever proposed

### latestProposalIds

```solidity
mapping(address => uint256) latestProposalIds
```

The latest proposal for each proposer

### ProposalCreated

```solidity
event ProposalCreated(uint256 id, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 startTime, uint256 endTime, string description)
```

An event emitted when a new proposal is created

### VoteCast

```solidity
event VoteCast(address voter, uint256 proposalId, bool support, uint256 firstQuorumVotes, uint256 secondQuorumVotes)
```

An event emitted when a vote has been cast on a proposal

### ProposalCanceled

```solidity
event ProposalCanceled(uint256 id)
```

An event emitted when a proposal has been canceled

### ProposalQueued

```solidity
event ProposalQueued(uint256 id, uint256 eta)
```

An event emitted when a proposal has been queued in the Timelock

### ProposalExecuted

```solidity
event ProposalExecuted(uint256 id)
```

An event emitted when a proposal has been executed in the Timelock

### MultisigTransferred

```solidity
event MultisigTransferred(address previousAddress, address newAddress)
```

Emitted when the 'multisig' address has been changed

### TimelockTransferred

```solidity
event TimelockTransferred(address previousAddress, address newAddress)
```

Emitted when the 'timelock' address has been changed

### onlyTimelock

```solidity
modifier onlyTimelock()
```

### constructor

```solidity
constructor(contract IVoteWeigher _VOTE_WEIGHTER, contract IQuorumRegistry _REGISTRY, contract Timelock _timelock, address _multisig, uint16 _firstQuorumPercentage, uint16 _secondQuorumPercentage, uint16 _proposalThresholdFirstQuorumPercentage, uint16 _proposalThresholdSecondQuorumPercentage) public
```

### propose

```solidity
function propose(address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, string description) external returns (uint256)
```

### queue

```solidity
function queue(uint256 proposalId) external
```

### _queueOrRevert

```solidity
function _queueOrRevert(address target, uint256 value, string signature, bytes data, uint256 eta) internal
```

### execute

```solidity
function execute(uint256 proposalId) external payable
```

### cancel

```solidity
function cancel(uint256 proposalId) external
```

### getActions

```solidity
function getActions(uint256 proposalId) external view returns (address[] targets, uint256[] values, string[] signatures, bytes[] calldatas)
```

### getReceipt

```solidity
function getReceipt(uint256 proposalId, address voter) external view returns (struct Governor.Receipt)
```

### state

```solidity
function state(uint256 proposalId) public view returns (enum Governor.ProposalState)
```

### castVote

```solidity
function castVote(uint256 proposalId, bool support) external
```

### castVoteBySig

```solidity
function castVoteBySig(uint256 proposalId, bool support, uint8 v, bytes32 r, bytes32 s) external
```

### _castVote

```solidity
function _castVote(address voter, uint256 proposalId, bool support) internal
```

### setQuorumsAndThresholds

```solidity
function setQuorumsAndThresholds(uint16 _firstQuorumPercentage, uint16 _secondQuorumPercentage, uint16 _proposalThresholdFirstQuorumPercentage, uint16 _proposalThresholdSecondQuorumPercentage) external
```

### _setQuorumsAndThresholds

```solidity
function _setQuorumsAndThresholds(uint16 _firstQuorumPercentage, uint16 _secondQuorumPercentage, uint16 _proposalThresholdFirstQuorumPercentage, uint16 _proposalThresholdSecondQuorumPercentage) internal
```

### setMultisig

```solidity
function setMultisig(address _multisig) external
```

### _setMultisig

```solidity
function _setMultisig(address _multisig) internal
```

### getChainId

```solidity
function getChainId() internal view returns (uint256)
```

### setTimelock

```solidity
function setTimelock(contract Timelock _timelock) external
```

### _setTimelock

```solidity
function _setTimelock(contract Timelock _timelock) internal
```

### _getVoterStakes

```solidity
function _getVoterStakes(address user) internal view returns (uint96, uint96)
```

