// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
/**
 * @title DataLayr
 * @dev L1 contracts that handles DataLayr Node registration
 *
 */

import "../../interfaces/IERC20.sol";
import "../../interfaces/DataLayrInterfaces.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DataLayr is Ownable, IDataLayr {
    using ECDSA for bytes32;

    address public currDisperser;
    IERC20 paymentToken;

    // Data Store
    struct DataStore {
        uint64 dumpNumber;
        uint32 initTime; //when the store was inited
        uint32 storePeriodLength; //when store expires
        uint24 quorum; //num signatures required for commit
        address submitter; //address approved to submit signatures for this datastore
        bool commited; //whether the data has been certified available
    }

    event DataStoreInit(
        address initializer, //person initing store
        bytes32 ferkleRoot, //counter-esque id
        uint256 totalBytes, //number of bytes in store including redundant chunks, basicall the total number of bytes in all frames of the FRS Merkle Tree
        uint24 quorum //percentage of nodes needed to certify receipt
    );

    mapping(bytes32 => DataStore) public dataStores;

    event Commit(
        address disperser,
        bytes32 ferkleRoot
    );

    // Data Layr Nodes
    struct Registrant {
        string socket; // how people can find it
        uint32 id; // id is always unique
        uint256 index; // corresponds to registrantList
        uint32 from;
        uint32 to;
        bool active; //bool
        uint256 stake;
    }

    event Registration(
        uint8 typeEvent, // 0: addedMember, 1: leftMember
        uint32 initiator, // who started
        uint32 numRegistrant,
        string initiatorSocket
    );

    //uint public churnRatio; //unit of 100 over 1 days

    // Register, everyone is active in the list
    mapping(address => Registrant) public registry;
    address[] public registrantList;
    uint32 public numRegistrant;
    uint32 public nextRegistrantId;

    // Challenges

    event ChallengeSuccess(
        address challenger,
        address adversary,
        bytes32 ferkleRoot,
        uint16 challengeType // ChallengeType: 0 - Signature, 1 - Coding
    );

    // Misc
    mapping(bytes32 => mapping(address => bool)) public isCodingProofDLNActive;

    // Constructor

    constructor(address currDisperser_) {
        currDisperser = currDisperser_;
        nextRegistrantId = 1;
    }

    // Precommit

    function initDataStore(
        uint64 dumpNumber,
        bytes32 ferkleRoot,
        uint32 totalBytes,
        uint32 storePeriodLength,
        address submitter,
        uint24 quorum
    ) external payable {
        require(msg.sender == currDisperser, "Only current disperser can init");
        require(totalBytes > 32, "Can't store less than 33 bytes");
        require(
            storePeriodLength > 1 * 60,
            "Expiry must be at least 1 minute after initialization"
        );
        require(
            dataStores[ferkleRoot].initTime == 0,
            "Data store has already been inited"
        );

        //initializes data store

        // Create datastore
        dataStores[ferkleRoot] = DataStore(
            dumpNumber,
            uint32(block.timestamp),
            storePeriodLength,
            quorum,
            submitter,
            false
        );

        emit DataStoreInit(
            msg.sender,
            ferkleRoot,
            totalBytes,
            quorum
        );
    }

    // Commit

    function confirm(
        uint64 dumpNumber,
        bytes32 ferkleRoot,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint8[] calldata vs
    ) external payable {
        DataStore storage dataStore = dataStores[ferkleRoot];
        require(
            msg.sender == dataStore.submitter,
            "Not authorized to submit signatures for this datastore"
        );
        require(
            dumpNumber == dataStore.dumpNumber,
            "Dump Number is incorrect"
        );
        require(
            !dataStores[ferkleRoot].commited,
            "Data store already has already been committed"
        );
        verifySignature(rs, ss, vs, ferkleRoot);
        dataStores[ferkleRoot].commited = true;
        emit Commit(
            msg.sender,
            ferkleRoot
        );
    }

    function verifySignature(
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        uint8[] calldata vs,
        bytes32 ferkleRoot
    ) internal view {
        for (uint256 i = 0; i < rs.length; i++) {
            address addr = ecrecover(ferkleRoot, 27 + vs[i], rs[i], ss[i]);
            require(registry[addr].active, "addr not exist");
        }
    }

    // Setters and Getters
}
