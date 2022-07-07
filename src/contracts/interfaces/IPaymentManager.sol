// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IRepositoryAccess.sol";

// TODO: provide more functions for this spec
interface IPaymentManager is IRepositoryAccess {	    
    function paymentFraudProofInterval() external view returns (uint256);

    function paymentFraudProofCollateral() external view returns (uint256);

    function getPaymentCollateral(address) external view returns (uint256);

    function paymentToken() external view returns(IERC20);

    function collateralToken() external view returns(IERC20);
    
    function depositFutureFees(address onBehalfOf, uint256 amount) external;

}