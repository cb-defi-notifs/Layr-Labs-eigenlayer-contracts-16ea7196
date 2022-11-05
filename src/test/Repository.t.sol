// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../test/TestHelper.t.sol";

contract RepositoryTests is TestHelper {
    /**
     * @notice this function tests inititalizing a repository
     * multiple times and ensuring that it reverts.
     */
    function testCannotInitMultipleTimesRepository() public {
        //repository has already been initialized in the Deployer test contract
        cheats.expectRevert(bytes("Initializable: contract is already initialized"));
        Repository(address(testRepository)).initialize(dlReg, dlsm, dlReg, address(this));
    }

    /**
     * @notice this function ensures that the owner of the repository can set all of its attributes.
     */
    function testOwnerPermissionsRepository() public {
        address repositoryOwner = Repository(address(testRepository)).owner();
        cheats.startPrank(repositoryOwner);
        Repository(address(testRepository)).setRegistry(dlReg);
        Repository(address(testRepository)).setServiceManager(dlsm);
        Repository(address(testRepository)).setVoteWeigher(dlReg);
        cheats.stopPrank();
    }
}
