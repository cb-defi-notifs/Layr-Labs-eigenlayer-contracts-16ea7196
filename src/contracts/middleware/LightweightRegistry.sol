// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IServiceManager.sol";
import "../interfaces/IRegistry.sol";
import "./Repository.sol";
import "./VoteWeigherBase.sol";

import "ds-test/test.sol";

/**
 * @notice This contract is used for 
            - registering new operators 
            - committing to and finalizing de-registration as an operator 
            - updating the stakes of the operator
 */

contract LightweightRegistry is
    IRegistry,
    VoteWeigherBase
    
{
    // DATA STRUCTURES 
    /**
     * @notice  Data structure for storing info on operators to be used for:
     *           - sending data by the sequencer
     *           - payment and associated challenges
     */
    struct Registrant {
        // start block from which the  operator has been registered
        uint32 fromBlockNumber;

        // block until which operator is slashable, 0 if not in unbonding period
        uint32 slashableUntil;

        // indicates whether the operator is actively registered for storing data or not 
        uint8 active; //bool

        uint96 stake;
    }

    // CONSTANTS
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant REGISTRATION_TYPEHASH =
        keccak256(
            "Registration(address operator,address registrationContract,uint256 expiry)"
        );

    // number of registrants of this service
    uint64 public numRegistrants;  

    uint128 public nodeEthStake = 1 wei;
    
    /// @notice EIP-712 Domain separator
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice used for storing Registrant info on each operator while registration
    mapping(address => Registrant) public registry;



    // EVENTS
    event StakeAdded(
        address operator,
        uint96 stake
    );
    // uint48 prevUpdatetaskNumber

    event StakeUpdate(
        address operator,
        uint96 stake
    );

    /**
     * @notice
     */
    event Registration(
        address registrant
    );

    event Deregistration(
        address registrant
    );

    constructor(
        Repository _repository,
        IEigenLayrDelegation _delegation,
        IInvestmentManager _investmentManager,
        StrategyAndWeightingMultiplier[] memory _ethStrategiesConsideredAndMultipliers
    )
        VoteWeigherBase(
            _repository,
            _delegation,
            _investmentManager,
            1
        )
    {
        //apk_0 = g2Gen
        // initialize the DOMAIN_SEPARATOR for signatures
        // initialize the DOMAIN_SEPARATOR for signatures
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, bytes("EigenLayr"), block.chainid, address(this))
        );

        _addStrategiesConsideredAndMultipliers(0, _ethStrategiesConsideredAndMultipliers);
    }

    /**
      @notice Used by an operator to de-register itself from providing service to the middleware.
     */
    /** 
     */
    function deregisterOperator() external virtual returns (bool) {
        _deregisterOperator();
        return true;
    }

    function _deregisterOperator() internal {
        require(
            registry[msg.sender].active > 0,
            "Operator is already registered"
        );

        /**
         @notice this info is used in retroactive proofs
         */
        registry[msg.sender].slashableUntil = uint32(block.number + 50400); // 7 days assuming blocks every 12.5 secs


        // committing to not being subjected to middleware slashing conditions from this point forward
        registry[msg.sender].active = 0;

        //decrement number of registrants
        unchecked {
            --numRegistrants;
        }

        emit Deregistration(msg.sender);
    }

    /**
     * @notice Used for updating information on ETH and EIGEN deposits of nodes.
     */
    /**
     * @param operators are the nodes whose information on their ETH and EIGEN deposits
     *        getting updated
     */
    function updateStakes(address[] calldata operators) public {
        uint256 operatorsLength = operators.length;
        // iterating over all the tuples that are to be updated
        for (uint256 i = 0; i < operatorsLength; ) {
            //get current wight and update accordingly
            uint96 stake = weightOfOperator(operators[i], 0);

            // check if minimum requirements have been met
            if (stake < nodeEthStake) {
                stake = uint96(0);
            }

            registry[operators[i]].stake = stake;

            emit StakeUpdate(
                operators[i],
                stake
            );
            unchecked {
                ++i;
            }
        }
    }


    /**
     @notice returns task number from when operator has been registered.
     */
    function getOperatorFromBlockNumber(address operator)
        public
        view
        returns (uint32)
    {
        return registry[operator].fromBlockNumber;
    }

    function setNodeEthStake(uint128 _nodeEthStake)
        external
        onlyRepositoryGovernance
    {
        nodeEthStake = _nodeEthStake;
    }

    /// @notice returns the active status for the specified operator
    function getOperatorType(address operator) public view returns (uint8) {
        return registry[operator].active;
    }

    /**
     @notice called for registering as a operator
     */
    function registerOperator() public virtual {        
        _registerOperator(msg.sender);
    }


    /**
     @param operator is the node who is registering to be a operator
     */
    function _registerOperator(
        address operator
    ) internal virtual {
        require(
            registry[operator].active == 0,
            "Operator is already registered"
        );

        uint96 stake = uint96(weightOfOperator(operator, 0));
        require(
            stake >= nodeEthStake,
            "Not enough eth value staked"
        );
        
        
        // store the registrant's info in relation
        registry[operator] = Registrant({
            active: 1,
            fromBlockNumber: uint32(block.number),
            slashableUntil: 0,
            stake: stake
        });

        // increment number of registrants
        unchecked {
            ++numRegistrants;
        }
            
        emit Registration(operator);
    }


    function ethStakedByOperator(address operator) external view returns (uint96) {
        return registry[operator].stake;
    }

    function isRegistered(address operator) external view returns (bool) {
        return registry[operator].stake > 0;
    }

    function getOperatorStatus(address operator) external view returns(uint8) {
        return registry[operator].active;
    }

    /**
     @notice returns task number from when operator has been registered.
     */
    function getFromBlockNumberForOperator(address operator)
        public
        view
        returns (uint32)
    {
        return registry[operator].fromBlockNumber;
    }
}