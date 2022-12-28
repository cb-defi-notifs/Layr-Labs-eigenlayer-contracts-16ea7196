pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT
import { FlagHelper } from "../munged/libraries/FlagHelper.sol";

interface IStakeHouseUniverse {
    function memberKnotToStakeHouse(bytes memory _memberId) external view returns (address);
}

/// @title StakeHouse core member registry. Functionality is built around this core
/// @dev Every member is known as a KNOT and the StakeHouse is a collection of KNOTs
contract MockStakeHouseRegistry {
    using FlagHelper for uint16;

    /// @notice Member metadata struct - taking advantage of packing
    struct MemberInfo {
        uint160 applicant; // address of account that applied to add the KNOT to the StakeHouse registry
        uint80 knotMemberIndex; // index integer assigned to KNOT when added to the StakeHouse
        uint16 flags; // flags tracking the state of the KNOT i.e. whether active, kicked and or rage quit
    }

    IStakeHouseUniverse public universe;

    /// @notice Member information packed into 1 var - ETH 1 applicant address, KNOT index pointer and flag info
    mapping(bytes => MemberInfo) public memberIDToMemberInfo;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _universe) {
        universe = IStakeHouseUniverse(_universe);
    }
    
    function getMemberInfo(bytes memory _memberId) public view returns (
        address applicant,      // Address of ETH account that added the member to the StakeHouse
        uint256 knotMemberIndex,// KNOT Index of the member within the StakeHouse
        uint16 flags,          // Flags associated with the member
        bool isActive           // Whether the member is active or knot
    ) {
        MemberInfo storage memberInfo = memberIDToMemberInfo[_memberId];
        applicant = address(memberInfo.applicant);
        knotMemberIndex = uint256(memberInfo.knotMemberIndex);
        flags = memberInfo.flags;
        isActive = _isActiveMember(_memberId, flags);
    }

    /// @dev given member flag values, determines if a member is active or not
    function _isActiveMember(bytes memory _memberId, uint16 _memberFlags) internal view returns (bool) {
        require(_memberFlags.exists(), "Invalid member");
        return _memberFlags.exists()
            && !_memberFlags.isKicked()
            && !_memberFlags.hasRageQuit()
            && universe.memberKnotToStakeHouse(_memberId) == address(this);
    }
}
