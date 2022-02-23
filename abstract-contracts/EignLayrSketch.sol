// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

abstract contract Governance {
    //highest level access control database
    address public accessControl;
    //highest level invesment management contract
    address public masterInvestor;
    //highest level contract for tracking registered stakers / users
    address public masterRegistry;
}

abstract contract AccessControl {
    //role => unique holder of role
    mapping(bytes32 => address) public uniqueRoleHolders;
    //role => address => whether address holds role or not
    mapping(bytes32 => mapping(address => bool)) public roleHolders;
    function lookupRole(string memory toLookup) public returns(bytes32);
    modifier onlyRole(bytes32 role) {
        require(roleHolders[role][msg.sender], abi.encode('onlyRole:', role));
        _;
    }
}

abstract contract MasterInvestor {
    //keep list of all investor contracts in the system
    //probably some emergency stop mechanisms?
    //possibly address => list of all investor contracts they are in 

}

abstract contract IInvestor {
    //mapping(address => bool) public tokenAccepted;
    function tokenAccepted(address tokenAddress) public view returns(bool);
    function shares(address tokenAddress, address user) public view returns(uint256);\
    mapping(address => uint256) public totalShares;
    function deposit(address tokenAddress, address to) public;
    function withdraw(address tokenAddress, uint256 amount, address to) public;
    //returns the best estimate of this contract's balance of a token, without updating state
    function balanceOfView(address tokenAddress) public view returns(uint256);
    //returns this contract's balance of a token
    function balanceOf(address tokenAddress) public returns(uint256);
    function sharesToUnderlyingView(address tokenAddress, uint256 amountShares) public view returns(uint256) {
        if (totalShares[tokenAddress] == 0) {
            return 0;
        } else {
            return (balanceOfView(tokenAddress) * amountShares) / totalShares[tokenAddress];
        }
    }
    function sharesToUnderlying(address tokenAddress, uint256 amountShares) public returns(uint256) {
        if (totalShares[tokenAddress] == 0) {
            return 0;
        } else {
            return (balanceOf(tokenAddress) * amountShares) / totalShares[tokenAddress];
        }
    }
    function underlyingToSharesView(address tokenAddress, uint256 amountUnderlying) public view returns(uint256) {
        if (totalShares[tokenAddress] == 0) {
            return amountUnderlying;
        } else {
            return (amountUnderlying * totalShares[tokenAddress]) / balanceOfView(tokenAddress);
        }
    }
    function underlyingToShares(address tokenAddress, uint256 amountUnderlying) public returns(uint256) {
        if (totalShares[tokenAddress] == 0) {
            return amountUnderlying;
        } else {
            return (amountUnderlying * totalShares[tokenAddress]) / balanceOf(tokenAddress);
        }
    }
    function userUnderlying(address tokenAddress, address user) public returns(uint256) {
        return sharesToUnderlying(shares(tokenAddress, user));
    }
    function userUnderlyingView(address tokenAddress, address user) public view returns(uint256) {
        return sharesToUnderlyingView(shares(tokenAddress, user));
    }
}

abstract contract WeightingFunction {
    address public tokenAddress;
    //weights for each address
    mapping(address => uint256) public weights;

    event WeightUpdated(address indexed user, uint256 newWeight);

    function updateUserWeight(address user) public {
        IInvestor[] memory managers = getAllInvestorContracts(user);
        uint256 previousWeight = weights[user];
        uint256 newWeight;
        for (uint256 i = 0; i < managers.length; i++) {
            newWeight += managers[i].userUnderlying(tokenAddress, user);
        }
        weights[user] = newWeight;
        emit WeightUpdated(user, newWeight);
        _updateWeightOnServiceRegistries(user, previousWeight, newWeight);
    }

    function _updateWeightOnServiceRegistries(address user, uint256 previousWeight, uint256 newWeight) internal {
        //get list of all service registries that the user is on
        //update their weight on each one
    }
}

abstract contract ServiceRegistry {
    //mapping of all registered operators
    mapping(address => bool) public operators;
    //sum of weights of all users
    uint256 public totalWeight;
    //weighting function used by the service
    address public weightingFunction;
    //TODO: should be permissioned
    function updateUserWeight(uint256 previousWeight, uint256 newWeight) public {
        if (previousWeight < newWeight) {
            totalWeight += (newWeight - previousWeight);
        } else {
            totalWeight -= (previousWeight - newWeight);
        }
    }

    function registerAsOperator() public {
        operators[msg.sender] = true;
        WeightingFunction(weightingFunction).updateUserWeight(msg.sender);
    } 
}
























