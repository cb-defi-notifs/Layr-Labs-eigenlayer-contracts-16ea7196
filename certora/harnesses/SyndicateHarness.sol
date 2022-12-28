pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

import "../munged/syndicate/Syndicate.sol";
import { ISlotSettlementRegistry } from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ISlotSettlementRegistry.sol";
import { IStakeHouseUniverse } from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IStakeHouseUniverse.sol";

contract SyndicateHarness is Syndicate {
    address registry;
    address universe;

    // function call_registerKnotsToSyndicate(bytes memory input) public {
    //     bytes[] memory next_input = new bytes[](1);
    //     next_input[0] = input;
    //     registerKnotsToSyndicate(next_input);
    // }

    // function call_addPriorityStakers(address input) public {
    //     address[] memory next_input = new address[](1);
    //     next_input[0] = input;
    //     addPriorityStakers(next_input);
    // }

    // function call_deRegisterKnots(bytes memory input) public {
    //     bytes[] memory next_input = new bytes[](1);
    //     next_input[0] = input;
    //     deRegisterKnots(next_input);
    // }

    // function call_stake(bytes memory input1, uint256 input2, address input3) public {
    //     bytes[] memory next_input1 = new bytes[](1);
    //     next_input1[0] = input1;
    //     uint256[] memory next_input2 = new uint256[](1);
    //     next_input2[0] = input2;
    //     stake(next_input1, next_input2, input3);
    // }

    // function call_unstake(address input1, address input2, bytes memory input3, uint256 input4) public {
    //     bytes[] memory next_input3 = new bytes[](1);
    //     next_input3[0] = input3;
    //     uint256[] memory next_input4 = new uint256[](1);
    //     next_input4[0] = input4;
    //     unstake(input1, input2, next_input3, next_input4);
    // }

    // function call_claimAsStaker(address input1, bytes memory input2) public {
    //     bytes[] memory next_input2 = new bytes[](1);
    //     next_input2[0] = input2;
    //     claimAsStaker(input1, next_input2);
    // }

    // function call_claimAsCollateralizedSLOTOwner(address input1, bytes memory input2) public {
    //     bytes[] memory next_input2 = new bytes[](1);
    //     next_input2[0] = input2;
    //     claimAsCollateralizedSLOTOwner(input1, next_input2);
    // }

    // function call1_batchUpdateCollateralizedSlotOwnersAccruedETH(bytes memory _blsPubKey) public {
    //     bytes[] memory _blsPubKeys = new bytes[](1);
    //     _blsPubKeys[0] = _blsPubKey;
    //     batchUpdateCollateralizedSlotOwnersAccruedETH(_blsPubKeys);
    // }

    // function call2_batchUpdateCollateralizedSlotOwnersAccruedETH(bytes memory _blsPubKey1, bytes memory _blsPubKey2) public {
    //     bytes[] memory _blsPubKeys = new bytes[](2);
    //     _blsPubKeys[0] = _blsPubKey1;
    //     _blsPubKeys[1] = _blsPubKey2;
    //     batchUpdateCollateralizedSlotOwnersAccruedETH(_blsPubKeys);
    // }

    // getters
    function get_accruedEarningPerCollateralizedSlotOwnerOfKnot(bytes memory blsPubKey, address sender) public view returns (uint256) {
        return accruedEarningPerCollateralizedSlotOwnerOfKnot[blsPubKey][sender];
    }

    function get_totalETHProcessedPerCollateralizedKnot(bytes memory blsPubKey) external view returns (uint256) {
        return totalETHProcessedPerCollateralizedKnot[blsPubKey];
    }

    function get_sETHStakedBalanceForKnot(address user, bytes memory knot) public view returns (uint256) {
        return sETHStakedBalanceForKnot[knot][user];
    }
    function get_sETHTotalStakeForKnot(bytes memory knot) public view returns (uint256) {
        return sETHTotalStakeForKnot[knot];
    }
    
    // overridden functions
    function getSlotRegistry() internal view override returns (ISlotSettlementRegistry slotSettlementRegistry) {
        return ISlotSettlementRegistry(registry);
    }

    function getStakeHouseUniverse() internal view override returns (IStakeHouseUniverse stakeHouseUniverse) {
        return IStakeHouseUniverse(universe);
    }

}

