// //SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "../../contracts/pods/BeaconChainOracle.sol";

import "forge-std/Test.sol";

contract BeaconChainOracleUnitTests is Test {

    Vm cheats = Vm(HEVM_ADDRESS);

    BeaconChainOracle public beaconChainOracle;

    address public initialBeaconChainOwner = address(this);
    uint256 public initialBeaconChainOracleThreshold = 3;

    mapping(address => bool) public addressIsExcludedFromFuzzedInputs;

    modifier filterFuzzedAddressInputs(address fuzzedAddress) {
        cheats.assume(!addressIsExcludedFromFuzzedInputs[fuzzedAddress]);
        _;
    }

    function setUp() external {
        beaconChainOracle = new BeaconChainOracle(initialBeaconChainOwner, initialBeaconChainOracleThreshold);
    }

    function testSetThreshold(uint256 newThreshold) external {
        // filter out disallowed inputs
        cheats.assume(newThreshold >= 2);
    }
}