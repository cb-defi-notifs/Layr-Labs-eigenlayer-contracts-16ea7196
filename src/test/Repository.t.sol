// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;


import "forge-std/Test.sol";
import "../test/Deployer.t.sol";




contract RepositoryTests is EigenLayrDeployer{

        function testCannotInitMultipleTimesRepository() public {
            //repository has already been initialized in the Deployer test contract
            cheats.expectRevert(
                bytes("Initializable: contract is already initialized")
            );
            Repository(address(dlRepository)).initialize(
                dlReg,
                dlsm,
                dlReg,
                address(this)
            );
        }
        function testOwnerPermissionsRepository() public {
            address repositoryOwner = Repository(address(dlRepository)).owner();
            cheats.startPrank(repositoryOwner);
            Repository(address(dlRepository)).setRegistry(dlReg);
            Repository(address(dlRepository)).setServiceManager(dlsm);
            Repository(address(dlRepository)).setVoteWeigher(dlReg);
            cheats.stopPrank();
        }
    }