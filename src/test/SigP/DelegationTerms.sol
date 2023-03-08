pragma solidity ^0.8.9;

import "../../contracts/strategies/InvestmentStrategyBase.sol";
import "../../contracts/interfaces/IEigenLayerDelegation.sol";


contract SigPDelegationTerms is IDelegationTerms {
    uint256 public paid;
    bytes public isDelegationWithdrawn;
    bytes public isDelegationReceived;


    function payForService(IERC20 /*token*/, uint256 /*amount*/) external payable {
        paid = 1;
    }

    function onDelegationWithdrawn(
        address /*delegator*/,
        IInvestmentStrategy[] memory /*investorStrats*/,
        uint256[] memory /*investorShares*/
    ) external returns(bytes memory) {
        isDelegationWithdrawn = bytes("withdrawn");
        bytes memory _isDelegationWithdrawn = isDelegationWithdrawn;
        return _isDelegationWithdrawn;
    }

    // function onDelegationReceived(
    //     address delegator,
    //     uint256[] memory investorShares
    // ) external;

    function onDelegationReceived(
        address /*delegator*/,
        IInvestmentStrategy[] memory /*investorStrats*/,
        uint256[] memory /*investorShares*/
    ) external returns(bytes memory) {
        // revert("test");
        isDelegationReceived = bytes("received");
        bytes memory _isDelegationReceived = isDelegationReceived;
        return _isDelegationReceived;
    }

    function delegate() external {
        isDelegationReceived = bytes("received");
    }
}
