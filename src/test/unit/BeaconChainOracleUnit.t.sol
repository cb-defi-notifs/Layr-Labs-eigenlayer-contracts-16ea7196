// //SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "../../contracts/pods/BeaconChainOracle.sol";

import "forge-std/Test.sol";

contract BeaconChainOracleUnitTests is Test {

    Vm cheats = Vm(HEVM_ADDRESS);

    BeaconChainOracle public beaconChainOracle;

    address public initialBeaconChainOwner = address(this);
    uint256 public initialBeaconChainOracleThreshold = 2;
    uint256 public minThreshold;

    mapping(address => bool) public addressIsExcludedFromFuzzedInputs;

    // static values reused across several tests
    uint256 numberPotentialOracleSigners = 16;
    address[] public potentialOracleSigners;
    uint64 public slotToVoteFor = 5151;
    bytes32 public stateRootToVoteFor = bytes32(uint256(987));

    modifier filterFuzzedAddressInputs(address fuzzedAddress) {
        cheats.assume(!addressIsExcludedFromFuzzedInputs[fuzzedAddress]);
        _;
    }

    function setUp() external {
        beaconChainOracle = new BeaconChainOracle(initialBeaconChainOwner, initialBeaconChainOracleThreshold);
        minThreshold = beaconChainOracle.MINIMUM_THRESHOLD();

        // set up array for use in testing
        for (uint256 i = 0; i < numberPotentialOracleSigners; ++i) {
            potentialOracleSigners.push(address(uint160(777 + i)));
        }
    }

    function testConstructor_RevertsOnThresholdTooLow() external {
        // check that deployment fails when trying to set threshold below `MINIMUM_THRESHOLD`
        cheats.expectRevert(bytes("BeaconChainOracle._setThreshold: cannot set threshold below MINIMUM_THRESHOLD"));
        new BeaconChainOracle(initialBeaconChainOwner, minThreshold - 1);

        // check that deployment succeeds when trying to set threshold *at* (i.e. equal to) `MINIMUM_THRESHOLD`
        beaconChainOracle = new BeaconChainOracle(initialBeaconChainOwner, minThreshold);
    }

    function testSetThreshold(uint256 newThreshold) public {
        // filter out disallowed inputs
        cheats.assume(newThreshold >= minThreshold);

        cheats.startPrank(beaconChainOracle.owner());
        beaconChainOracle.setThreshold(newThreshold);
        cheats.stopPrank();

        assertEq(newThreshold, beaconChainOracle.threshold());
    }

    function testSetThreshold_RevertsOnThresholdTooLow() external {
        cheats.startPrank(beaconChainOracle.owner());
        cheats.expectRevert(bytes("BeaconChainOracle._setThreshold: cannot set threshold below MINIMUM_THRESHOLD"));
        beaconChainOracle.setThreshold(minThreshold - 1);
        cheats.stopPrank();

        // make sure it works *at* (i.e. equal to) the threshold
        testSetThreshold(minThreshold);
    }

    function testSetThreshold_RevertsOnCallingFromNotOwner(address notOwner) external {
        cheats.assume(notOwner != beaconChainOracle.owner());

        cheats.startPrank(notOwner);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        beaconChainOracle.setThreshold(minThreshold);
        cheats.stopPrank();
    }

    function testAddOracleSigner(address signerToAdd) public {
        cheats.startPrank(beaconChainOracle.owner());
        beaconChainOracle.addOracleSigner(signerToAdd);
        cheats.stopPrank();

        require(beaconChainOracle.isOracleSigner(signerToAdd), "signer not added");
    }

    function testAddOracleSigner_SignerAlreadyInSet() external {
        address oracleSigner = potentialOracleSigners[0];
        testAddOracleSigner(oracleSigner);

        cheats.startPrank(beaconChainOracle.owner());
        beaconChainOracle.addOracleSigner(oracleSigner);
        cheats.stopPrank();

        require(beaconChainOracle.isOracleSigner(oracleSigner), "signer improperly removed");
    }

    function testAddOracleSigner_RevertsOnCallingFromNotOwner(address notOwner) external {
        cheats.assume(notOwner != beaconChainOracle.owner());

        cheats.startPrank(notOwner);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        beaconChainOracle.addOracleSigner(potentialOracleSigners[0]);
        cheats.stopPrank();

        require(!beaconChainOracle.isOracleSigner(potentialOracleSigners[0]), "signer improperly added");
    }

    function testVoteForBeaconChainStateRoot(address oracleSigner, uint64 _slot, bytes32 _stateRoot) public {
        uint256 votesBefore = beaconChainOracle.stateRootVotes(_slot, _stateRoot);

        testAddOracleSigner(oracleSigner);
        cheats.startPrank(oracleSigner);
        beaconChainOracle.voteForBeaconChainStateRoot(_slot, _stateRoot);
        cheats.stopPrank();

        uint256 votesAfter = beaconChainOracle.stateRootVotes(_slot, _stateRoot);
        require(votesAfter == votesBefore + 1, "votesAfter != votesBefore + 1");
        require(beaconChainOracle.hasVoted(_slot, oracleSigner), "vote not recorded as being cast");
        if (votesAfter == beaconChainOracle.threshold()) {
            assertEq(beaconChainOracle.beaconStateRoot(_slot), _stateRoot, "state root not confirmed when it should be");
        } else {
            require(beaconChainOracle.beaconStateRoot(_slot) == bytes32(0), "state root improperly confirmed");
        }
    }

    function testVoteForBeaconChainStateRoot_VoteDoesNotCauseConfirmation() public {
        address _oracleSigner = potentialOracleSigners[0];
        testVoteForBeaconChainStateRoot(_oracleSigner, slotToVoteFor, stateRootToVoteFor);
    }

    function testVoteForBeaconChainStateRoot_VoteCausesConfirmation(uint64 _slot, bytes32 _stateRoot) public {
        uint64 latestConfirmedOracleSlotBefore = beaconChainOracle.latestConfirmedOracleSlot();

        uint256 votesBefore = beaconChainOracle.stateRootVotes(_slot, _stateRoot);
        require(votesBefore == 0, "something is wrong, state root should have zero votes before voting");

        for (uint256 i = 0; i < beaconChainOracle.threshold(); ++i) {
            testVoteForBeaconChainStateRoot(potentialOracleSigners[i], _slot, _stateRoot);
        }

        assertEq(beaconChainOracle.beaconStateRoot(_slot), _stateRoot, "state root not confirmed when it should be");
        assertEq(beaconChainOracle.threshold(), beaconChainOracle.stateRootVotes(_slot, _stateRoot), "state root confirmed with incorrect votes");

        if (_slot > latestConfirmedOracleSlotBefore) {
            assertEq(_slot, beaconChainOracle.latestConfirmedOracleSlot(), "latestConfirmedOracleSlot did not update appropriately");
        } else {
            assertEq(latestConfirmedOracleSlotBefore, beaconChainOracle.latestConfirmedOracleSlot(), "latestConfirmedOracleSlot updated inappropriately");
        }
    }

    function testVoteForBeaconChainStateRoot_VoteCausesConfirmation_latestOracleSlotDoesNotIncrease() external {
        testVoteForBeaconChainStateRoot_VoteCausesConfirmation(slotToVoteFor + 1, stateRootToVoteFor);
        uint64 latestConfirmedOracleSlotBefore = beaconChainOracle.latestConfirmedOracleSlot();
        testVoteForBeaconChainStateRoot_VoteCausesConfirmation(slotToVoteFor, stateRootToVoteFor);
        assertEq(latestConfirmedOracleSlotBefore, beaconChainOracle.latestConfirmedOracleSlot(), "latestConfirmedOracleSlot updated inappropriately");
    }

    function testVoteForBeaconChainStateRoot_RevertsWhenCallerHasVoted() external {
        address _oracleSigner = potentialOracleSigners[0];
        testVoteForBeaconChainStateRoot(_oracleSigner, slotToVoteFor, stateRootToVoteFor);

        cheats.startPrank(_oracleSigner);
        cheats.expectRevert(bytes("BeaconChainOracle.voteForBeaconChainStateRoot: Signer has already voted"));
        beaconChainOracle.voteForBeaconChainStateRoot(slotToVoteFor, stateRootToVoteFor);
        cheats.stopPrank();
    }

    function testVoteForBeaconChainStateRoot_RevertsWhenStateRootAlreadyConfirmed() external {
        address _oracleSigner = potentialOracleSigners[potentialOracleSigners.length - 1];
        testAddOracleSigner(_oracleSigner);
        testVoteForBeaconChainStateRoot_VoteCausesConfirmation(slotToVoteFor, stateRootToVoteFor);

        cheats.startPrank(_oracleSigner);
        cheats.expectRevert(bytes("BeaconChainOracle.voteForBeaconChainStateRoot: State root already confirmed"));
        beaconChainOracle.voteForBeaconChainStateRoot(slotToVoteFor, stateRootToVoteFor);
        cheats.stopPrank();
    }

    function testVoteForBeaconChainStateRoot_RevertsWhenCallingFromNotOracleSigner(address notOracleSigner) external {
        cheats.startPrank(notOracleSigner);
        cheats.expectRevert(bytes("BeaconChainOracle.onlyOracleSigner: Not an oracle signer"));
        beaconChainOracle.voteForBeaconChainStateRoot(slotToVoteFor, stateRootToVoteFor);
        cheats.stopPrank();
    }
}