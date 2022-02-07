// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.9;

import "./utils/Ownable.sol";

contract MasterRegistry is Ownable {
	//contracts for depositing ETH. have their own weighting logic
	mapping(address => bool) public depositContracts;
	//for voting and/or rewards
	mapping(address => uint256) public userWeights;
	//how much ETH deposited
	mapping(address => uint256) public userStakes;
	//contracts that track registered stakers for different services
	mapping(bytes32 => address) public serviceRegistries;
	//slashing contracts related to different services
	mapping(bytes32 => address) public slashingContracts;
	//contracts that invest liquid ETH elsewhere
	mapping(address => bool) public managementContracts;

	modifier onlyDepositContracts() {
		require(depositContracts[msg.sender], "onlyDepositContracts");
		_;
	}

	event DepositContractAdded(address indexed contractAddress);
	event DepositContractRemoved(address indexed contractAddress);
	event ManagementContractAdded(address indexed contractAddress);
	event ManagementContractRemoved(address indexed contractAddress);
	event ServiceRegistryAdded(bytes32 indexed serviceIdenitifier, address indexed contractAddress);
	event ServiceRegistryRemoved(bytes32 indexed serviceIdenitifier, address indexed contractAddress);
	event ServiceSlasherAdded(bytes32 indexed serviceIdenitifier, address indexed slasherAddress);
	event ServiceSlasherRemoved(bytes32 indexed serviceIdenitifier, address indexed slasherAddress);
	event StakeUpdated(address indexed userAddress, uint256 newAmountStaked);
	event WeightUpdated(address indexed userAddress, uint256 newWeight);

	function creditDeposit(address userAddress, uint256 amountStaked, uint256 addedWeight) external onlyDepositContracts {
		if (amountStaked > 0) {
			uint256 newAmountStaked = userStakes[userAddress] + amountStaked;
			userStakes[userAddress] = newAmountStaked;
			emit StakeUpdated(userStakes[userAddress], newAmountStaked);
		}
		if (addedWeight > 0) {
			uint256 newWeight = userWeights[userAddress] + addedWeight;
			userWeights[userAddress] = newWeight;			
			emit WeightUpdated(userStakes[userAddress], newWeight);
		}
	}

	function updateUserWeight(address userAddress, uint256 newWeight) external onlyDepositContracts {
		if (newWeight != userWeights[userAddress]) {
			userWeights[userAddress] = newWeight;
			emit WeightUpdated(userAddress, newWeight);			
		}
	}

	function processWithdrawal(address userAddress, uint256 amountUnstaked, uint256 newWeight) external onlyDepositContracts {
		if (amountUnstaked > 0) {
			uint256 newAmountStaked = userStakes[userAddress] - amountUnstaked;
			userStakes[userAddress] = newAmountStaked;
			emit StakeUpdated(userStakes[userAddress], newAmountStaked);
		}
		if (newWeight != userWeights[userAddress]) {
			userWeights[userAddress] = newWeight;
			emit WeightUpdated(userAddress, newWeight);			
		}
	}

	function addDepositContracts(address[] calldata contractsToAdd) external onlyOwner {
		for (uint256 i = 0; i < contractsToAdd.length; i++) {
			if (!depositContracts[contractsToAdd[i]]) {
				depositContracts[contractsToAdd[i]] = true;
				emit DepositContractAdded(contractsToAdd[i]);
			}
		}
	}

	function removeDepositContracts(address[] calldata contractsToRemove) external onlyOwner {
		for (uint256 i = 0; i < contractsToRemove.length; i++) {
			if (depositContracts[contractsToRemove[i]]) {
				depositContracts[contractsToRemove[i]] = false;
				emit DepositContractRemoved(contractsToRemove[i]);
			}
		}
	}

	function addManagementContracts(address[] calldata contractsToAdd) external onlyOwner {
		for (uint256 i = 0; i < contractsToAdd.length; i++) {
			if (!managementContracts[contractsToAdd[i]]) {
				managementContracts[contractsToAdd[i]] = true;
				emit ManagementContractAdded(contractsToAdd[i]);
			}
		}
	}

	function removeManagementContracts(address[] calldata contractsToRemove) external onlyOwner {
		for (uint256 i = 0; i < contractsToRemove.length; i++) {
			if (managementContracts[contractsToRemove[i]]) {
				managementContracts[contractsToRemove[i]] = false;
				emit ManagementContractRemoved(contractsToRemove[i]);
			}
		}
	}

	function addServiceRegistries(bytes32[] calldata serviceIdentifiers, address[] calldata contractsToAdd, address[] calldata slashers) external onlyOwner {
		require(serviceIdentifiers.length == contractsToAdd.length && serviceIdentifiers.length == slashers.length, "input length mismatch");
		for (uint256 i = 0; i < serviceIdentifiers.length; i++) {
			if (serviceRegistries[serviceIdentifiers[i]] == address(0)) {
				serviceRegistries[serviceIdentifiers[i]] = contractsToAdd[i];
				emit ServiceRegistryAdded(serviceIdentifiers[i], contractsToAdd[i]);
				if (slashers[i] != address(0)) {
					slashingContracts[serviceIdentifiers[i]] = slashers[i];
					emit ServiceSlasherAdded(serviceIdentifiers[i], slashers[i]);
				}
			}
		}
	}

	function removeServiceRegistries(bytes32[] calldata serviceIdentifiers) external onlyOwner {
		for (uint256 i = 0; i < serviceIdentifiers.length; i++) {
			if (serviceRegistries[serviceIdentifiers[i]] != address(0)) {
				emit ServiceRegistryRemoved(serviceIdentifiers[i], serviceRegistries[serviceIdentifiers[i]]);
				serviceRegistries[serviceIdentifiers[i]] = address(0);
				if (slashingContracts[serviceIdentifiers[i]] != address(0)) {
					emit ServiceSlasherRemoved(serviceIdentifiers[i], slashingContracts[serviceIdentifiers[i]]);
					slashingContracts[serviceIdentifiers[i]] = address(0);
				}
			}
		}
	}

	function updateServiceSlashers(bytes32[] calldata serviceIdentifiers, address[] calldata slashers) external onlyOwner {
		require(serviceIdentifiers.length == slashers.length, "input length mismatch");
		for (uint256 i = 0; i < serviceIdentifiers.length; i++) {
			if (serviceRegistries[serviceIdentifiers[i]] == address(0)) {
				if (slashers[i] != address(0)) {
					if (slashingContracts[serviceIdentifiers[i]] != address(0)) {
						emit ServiceSlasherRemoved(serviceIdentifiers[i], slashingContracts[serviceIdentifiers[i]]);
					}
					slashingContracts[serviceIdentifiers[i]] = slashers[i];
					emit ServiceSlasherAdded(serviceIdentifiers[i], slashers[i]);
				} else {
					if (slashingContracts[serviceIdentifiers[i]] != address(0)) {
						emit ServiceSlasherRemoved(serviceIdentifiers[i], slashingContracts[serviceIdentifiers[i]]);
						slashingContracts[serviceIdentifiers[i]] = address(0);
					}
				}
			}
		}
	}
}





