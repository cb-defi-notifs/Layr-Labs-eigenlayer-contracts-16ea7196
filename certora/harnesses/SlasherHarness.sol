// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../munged/core/Slasher.sol";

contract SlasherHarness is Slasher {

    constructor(IInvestmentManager _investmentManager, IEigenLayrDelegation _delegation) Slasher(_investmentManager, _delegation) {}
    
    /// Harnessed functions
    function get_is_operator(address staker) public returns (bool) {
        return delegation.isOperator(staker);        
    }

    function get_is_delegated(address staker) public returns (bool) {
        return delegation.isDelegated(staker);        
    }


    // Linked List Functions
    function get_list_exists(address operator) public returns (bool) {
        return StructuredLinkedList.listExists(operatorToWhitelistedContractsByUpdate[operator]);
    }

    function get_next_node_exists(address operator, uint256 node) public returns (bool) {
        (bool res, ) = StructuredLinkedList.getNextNode(operatorToWhitelistedContractsByUpdate[operator], node);
        return res;
    }

    function get_next_node(address operator, uint256 node) public returns (uint256) {
        (, uint256 res) = StructuredLinkedList.getNextNode(operatorToWhitelistedContractsByUpdate[operator], node);
        return res;
    }

    function get_previous_node_exists(address operator, uint256 node) public returns (bool) {
        (bool res, ) = StructuredLinkedList.getPreviousNode(operatorToWhitelistedContractsByUpdate[operator], node);
        return res;
    }

    function get_previous_node(address operator, uint256 node) public returns (uint256) {
        (, uint256 res) = StructuredLinkedList.getPreviousNode(operatorToWhitelistedContractsByUpdate[operator], node);
        return res;
    }

    function get_list_head(address operator) public returns (uint256) {
        return StructuredLinkedList.getHead(operatorToWhitelistedContractsByUpdate[operator]);
    }

    function get_lastest_update_block_at_node(address operator, uint256 node) public returns (uint256) {
        return _whitelistedContractDetails[operator][_uintToAddress(node)].latestUpdateBlock;
    }

    function get_lastest_update_block_at_head(address operator) public returns (uint256) {
        return get_lastest_update_block_at_node(operator, get_list_head(operator));
    }

    function get_linked_list_entry(address operator, uint256 node, bool direction) public returns (uint256) {
        return (operatorToWhitelistedContractsByUpdate[operator].list[node][direction]);
    }
    
}