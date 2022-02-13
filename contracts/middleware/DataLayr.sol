// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
/**
 * @title DataLayr
 * @dev L1 contracts that handles DataLayr Node registration
 *
 */

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DataLayr is Ownable {

    using ECDSA for bytes32;

    address public currDisperser;

    // Staking
    uint256 public dlnStake = 1 wei;

    // Data Store
    struct DataStore {
        uint256 feesPerDLNPerTime;                       //how much the store costed
        uint32 initTime;                   //when the store was inited
        uint32 storePeriodLength;                     //when store expires
        uint24  quorum;                     //num signatures required for commit
        address submitter;                  //address approved to submit signatures for this datastore
        uint256 commitSignaturesCollateral; //how much collateral was paid for signature submission
        bytes32 commitHash;                 //hash of the appended signatures
        uint32 commitTime;                 //time when signatures were commited
        uint24  numDLNSignedCodingProof;    //the number of DLN who stored this data
    }

    event DataStoreInit (
        address initializer,    //person initing store
        bytes32 ferkleRoot,     //counter-esque id
        uint32 initTime,       //when store is initialized
        uint32 expireTime,     //when store expires
        uint256 totalBytes,     //number of bytes in store including redundant chunks, basicall the total number of bytes in all frames of the FRS Merkle Tree
        uint24  quorum,         //percentage of nodes needed to certify receipt
        uint256 totalFeesPerDLN
    );

    mapping(bytes32 => DataStore) public dataStores;

    // seconds. This should be approximately equal to the duration for which items are typically stored
    uint32 constant expirationBinInterval = 1000;
    mapping(uint32 => bytes32[]) public ferkleRootsByExpiration; // Key is equal to floor(expirationTime / exirationBinInterval)
    uint32[] public initTimes;


    // Commit
    uint256 public signatureCommitFraudProofInterval = 60 seconds;
    uint256 public commitSignaturesCollateral = 1 wei;

    event Commit (
        address disperser,
        bytes32 commitHash,
        bytes32 ferkleRoot,
        uint32 time,
        uint32[] signatory
    );

    // precommit time => fees of all data stores inited at that time over the numRegistrants at that time
    mapping(uint32 => uint256) public cumulativeFeesPerDLN;
    uint256 lastCumulativeFeesPerDLN;

    uint256 public feePerBytePerTime = 1000000 wei;

    uint256 public paymentFraudProofInterval = 60 seconds;
    uint256 public commitPaymentCollateral = 1 wei;


    // Data Layr Nodes
    struct Registrant {
        string socket;   // how people can find it
        uint32 id;         // id is always unique
        uint32 oldestAncestor;
        uint256 index;      // corresponds to registrantList
        uint32 from;
        uint32 to;
        bool active; //bool
        uint256 stake;
    }

    struct Transition {
        uint32 leaver;
        uint32 bearer;
        uint expire;
    }

    event Registration (
        uint8 typeEvent,     // 0: addedMember, 1: leftMember
        uint32 initiator,    // who started
        uint32 target,       // who is responsible for loading, unloading
        uint32 numRegistrant,
        string initiatorSocket
    );

    //uint public churnRatio; //unit of 100 over 1 days

    // Register, everyone is active in the list
    mapping(address => Registrant) public registry;
    address[] public registrantList;
    uint32 public numRegistrant;
    uint32 public nextRegistrantId;

    // Delist
    mapping(uint => Transition) public transitQueue;
    uint public transitQueueFirst;
    uint public transitQueueLast;
    uint internal nextBearerIndex;

    // Challenges

    event ChallengeSuccess (
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
        transitQueueLast = 0;
        nextRegistrantId = 1;
    }

    // Registration and ETQ

    function register(string calldata socket_) public payable {
        require(msg.value == dlnStake, "Incorrect Stake");
        require(block.timestamp - registry[msg.sender].to > signatureCommitFraudProofInterval, "Must wait 1 fraud proof interval before reregistering");
        registry[msg.sender] = Registrant({
            socket: socket_,
            id: nextRegistrantId,
            oldestAncestor: nextRegistrantId,
            index: numRegistrant,
            active: true,
            from: uint32(block.timestamp),
            to: 0,
            stake: dlnStake
        });
        registrantList.push(msg.sender);
        nextRegistrantId++;
        numRegistrant++;

        if (getTransitQueueLength() > 0 && nextBearerIndex < transitQueueLast ) {
            uint32 bearer = inQueueChangeBearer(registry[msg.sender].id);
            emit Registration(0, registry[msg.sender].id, bearer, 0, socket_);
        } else {
            emit Registration(0, registry[msg.sender].id, registry[msg.sender].id, 0, socket_);
        }
    }

    // sender needs to be a registrant
    // TODO the delist happens immediately
    function scheduleDelist() public {
        // pay for fees
        require(registry[msg.sender].active == true, "sender should be active");
        uint32 rand = 1; // getRandomRegistrantIndex(msg.sender);
        enqueTransition(registry[msg.sender].id, registry[registrantList[rand]].id);
        string memory socket = registry[msg.sender].socket;

        //TODO not immediate
        delist();
        numRegistrant--;
        emit Registration(1, registry[msg.sender].id, rand, numRegistrant, socket);
    }

    function enqueTransition(uint32 leaver_, uint32 bearer_) internal {
        transitQueue[transitQueueLast] = Transition({
            leaver: leaver_,
            bearer: bearer_,
            expire: 0
        });
        transitQueueLast++;
    }

    function delist() public {
        // Can be moved to offchain
        //uint queueIndex;
        //for (uint i=transitQueueFirst; i<transitQueueLast; i++) {
        //    if ( transitQueue[i].leaver == registry[msg.sender].id ) {
        //        queueIndex = i;
        //        break;
        //    }
        //}
        
        //require(transitQueue[queueIndex].leaver == registry[msg.sender].id, "Only scheduled registrant can delist");
        //require(transitQueue[queueIndex].effective <= block.number, "Have to pass the starting effective date");
        address tail = registrantList[registrantList.length-1];
        uint256 index = registry[msg.sender].index;
        registry[tail].index = index;
        registrantList[index] = tail;
        registrantList.pop();

        registry[msg.sender].active = false;
        //delete registry[msg.sender];
    }

    function getTransitQueueLength() internal view returns (uint) {
        require(transitQueueLast>=transitQueueFirst, "Queue management is wrong");
        return transitQueueLast - transitQueueFirst;
    }

    function inQueueChangeBearer(uint32 bearer_) internal returns (uint32) {
        uint32 bearer = transitQueue[nextBearerIndex].bearer = bearer_;
        nextBearerIndex++;
        return bearer;
    }

    function dequeueTransition() internal returns (Transition memory rtransition) {
        require(transitQueueFirst<transitQueueLast, "Queue is empty");
        rtransition = transitQueue[transitQueueFirst];
        delete transitQueue[transitQueueFirst];
        transitQueueFirst++;
        if (nextBearerIndex > 0) {
            nextBearerIndex--;
        }
    }

    // TODO should only select ones that is active, not scheduled to leave
    // USE Block hash as a source of randomness
    //function getRandomRegistrantIndex(address a) internal view returns (uint) {
    //    bytes32 blockhash_ = blockhash(block.number);
    //    uint rand = uint(blockhash_) % numRegistrant;
    //    if (registrantList[rand] == a) {
    //        return (rand + 1) % numRegistrant; // getRandomRegistrantIndex(a)TODO hack later
    //    } else {
    //        return rand;
    //    }
    //}

    // Precommit

    function initDataStore(bytes32 ferkleRoot, uint32 totalBytes, uint32 storePeriodLength, address submitter, uint24 quorum) external payable {
        require(totalBytes > 32, "Can't store less than 33 bytes");
        require(storePeriodLength > 1*60, "Expiry must be at least 1 minute after initialization");
        require(dataStores[ferkleRoot].initTime == 0, "Data store has already been inited");
        uint256 fee = totalBytes * storePeriodLength * feePerBytePerTime;
        require(msg.value == fee, "Incorrect Fee paid");
        //initializes data store

        uint32 timestamp = uint32(block.timestamp);
        uint32 expiration = timestamp + storePeriodLength;
        uint32 expirationBin = expiration / expirationBinInterval;
        uint256 feesPerTimePerDLN = totalBytes * feePerBytePerTime / numRegistrant;

        // Create datastore
        dataStores[ferkleRoot] = DataStore(feesPerTimePerDLN, timestamp, storePeriodLength, quorum, submitter, commitSignaturesCollateral, bytes32(0), 0, 0);
        ferkleRootsByExpiration[expirationBin].push(ferkleRoot);

        // Update cumulative fees per DLN at current timestamp
        if(cumulativeFeesPerDLN[timestamp] == 0){
            cumulativeFeesPerDLN[timestamp] = lastCumulativeFeesPerDLN + feesPerTimePerDLN * storePeriodLength;
            initTimes.push(timestamp);
        } else {
            cumulativeFeesPerDLN[timestamp] += feesPerTimePerDLN * storePeriodLength;
        }
        lastCumulativeFeesPerDLN = cumulativeFeesPerDLN[timestamp];

        emit DataStoreInit(msg.sender, ferkleRoot, timestamp, expiration, totalBytes, quorum, feesPerTimePerDLN);
    }

    // Commit

    function commit(bytes calldata signatures, bytes32 ferkleRoot, uint32[] calldata signatory) external payable {
        DataStore storage dataStore = dataStores[ferkleRoot];
        require(signatures.length % 96 == 0, "Signatures incorrectly serialized");
        require(msg.sender == dataStore.submitter, "Not authorized to submit signatures for this datastore");
        require(msg.value == dataStore.commitSignaturesCollateral, "Incorrect collateral");
        require(dataStore.commitHash == bytes32(0), "Data store already has commitHash");
        bytes32 commitHash = keccak256(signatures);
        dataStores[ferkleRoot].commitHash = commitHash;
        dataStores[ferkleRoot].commitTime = uint32(block.timestamp);
        emit Commit(msg.sender, commitHash, ferkleRoot, uint32(block.timestamp), signatory);
    }

    function verifySignature(bytes32[] calldata rs, bytes32[] calldata ss, uint8[] calldata vs, bytes32 commitHash) view internal{
        for(uint i=0; i<rs.length; i++){
            address addr = ecrecover(commitHash, 27 + vs[i], rs[i], ss[i]);
            require(registry[addr].active, "addr not exist");
        }
    }

    function redeemCommitCollateral(bytes32 ferkleRoot) external payable {
        DataStore storage dataStore = dataStores[ferkleRoot];
        require(
            address(0) != dataStore.submitter,
            "Datastore has not been initialized or it was fraudulent"
        );
        require(
            block.timestamp >
                dataStore.commitTime + signatureCommitFraudProofInterval,
            "Fraud proof period has not passed"
        );
        Address.sendValue(
            payable(dataStore.submitter),
            dataStore.commitSignaturesCollateral
        );
    }

    // Signature Challenge

    function challengeCommitSignatures(bytes32 ferkleRoot, bytes32[] calldata rs, bytes32[] calldata ss, uint256[] calldata vs, uint256 fraudIndex) external {
        DataStore storage dataStore = dataStores[ferkleRoot];
        require(block.timestamp < dataStore.commitTime + signatureCommitFraudProofInterval, "Data store doesn't exist");
        require(dataStore.commitHash == keccak256(abi.encodePacked(rs, ss, vs)), "Data store doesn't have commitHash");
        //signatures are a quorum
        uint v = 27 + vs[fraudIndex];
        address registrant = ecrecover(ferkleRoot, uint8(v), rs[fraudIndex], ss[fraudIndex]);

        require(
            registry[registrant].oldestAncestor > dataStore.initTime ||
            registry[registrant].id == 0, "Signature is from valid registrant"
        );
    
        Address.sendValue(payable(msg.sender), dataStore.commitSignaturesCollateral);
    
        dataStores[ferkleRoot].commitHash = bytes32(0);
        dataStores[ferkleRoot].submitter = address(0);
        emit ChallengeSuccess(dataStore.submitter, msg.sender, ferkleRoot, 0);
    }

    // Coding Challenge

    function challengeCommitCoding(bytes32 ferkleRoot, bytes32[] calldata rs, bytes32[] calldata ss, uint8[] calldata vs) external {
        require(rs.length >= ceil(numRegistrant, 2), "Insufficient sig");
        
        DataStore storage dataStore = dataStores[ferkleRoot];
        require(block.timestamp < dataStore.commitTime + signatureCommitFraudProofInterval, "Data store doesn't have commitHash");
        //uint24 numNewDLNSignedCodingProof = 0;
        //signatures are a quorum
        //for(uint i = 0; i < rs.length; i++){
        //    address registrant = ecrecover(ferkleRoot, 27 + vs[i], rs[i], ss[i]);
            //if DLN has already been proven active, don't count it twice
        //    if(isCodingProofDLNActive[ferkleRoot][registrant]){
        //        continue;
        //    }
            //check that registrant is active now
        //    require(registry[registrant].active, "Registrant is not active");
        //    isCodingProofDLNActive[ferkleRoot][registrant] = true;
        //    numNewDLNSignedCodingProof++;
       // }

        //if(dataStore.numDLNSignedCodingProof + numNewDLNSignedCodingProof > dataStore.quorum){
        verifySignature(rs, ss, vs, keccak256(abi.encodePacked(ferkleRoot)));
        Address.sendValue(payable(msg.sender), dataStore.commitSignaturesCollateral/2);
        dataStores[ferkleRoot].commitHash = bytes32(0);
        dataStores[ferkleRoot].submitter = address(0);
        emit ChallengeSuccess(dataStore.submitter, msg.sender, ferkleRoot, 1);
        //} else {
        //    dataStores[ferkleRoot].numDLNSignedCodingProof += numNewDLNSignedCodingProof;
        //}
    }

    
    // Setters and Getters

    function setDlnStake(uint256 _dlnStake) public onlyOwner {
        dlnStake = _dlnStake;
    }
    
    function setSignatureCommitFraudProofInterval(uint256 _signatureCommitFraudProofInterval) public onlyOwner {
        signatureCommitFraudProofInterval = _signatureCommitFraudProofInterval;
    }

    function seCommitSignaturesCollateral(uint256 _commitSignaturesCollateral) public onlyOwner {
        commitSignaturesCollateral = _commitSignaturesCollateral;
    }

    // Utils

    function ceil(uint a, uint b) pure internal returns (uint) {
        require(b>0);
        return (a + b - 1) / b;
    }
}
