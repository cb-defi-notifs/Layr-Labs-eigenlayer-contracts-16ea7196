// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9.0;

import "./IPaymentManager.sol";
import "./IDataLayrServiceManager.sol";

/**
 * @title Minimal interface extension to `IPaymentManager`.
 * @author Layr Labs, Inc.
 * @notice Adds a single DataLayr-specific function to the base interface.
*/
interface IDataLayrPaymentManager is IPaymentManager {
    function respondToPaymentChallengeFinal(
        address operator,
        uint256 stakeIndex,
        uint48 nonSignerIndex,
        bytes32[] memory nonSignerPubkeyHashes,
        TotalStakes calldata totalStakes,
        IDataLayrServiceManager.DataStoreSearchData calldata searchData
    )
        external;
}
