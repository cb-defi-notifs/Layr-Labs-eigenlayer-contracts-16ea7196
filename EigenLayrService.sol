import "./interfaces/IERC20.sol";
import "./interfaces/EigenLayrInterfaces.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract EigenLayrService is IEigenLayrService {
    IEigenLayrFeePayer public feePayer;
    IEigenLayrVoteWeigher public voteWeigher;
    string public explanation;
    uint256 public nextQueryId = 0;
    mapping(uint256 => Query) public queries;
    uint256 public resolveTimeSinceLastVote;
    struct Query {
        uint256 startTime;
        bool resolved;
        uint256 lastVoteTime;
        mapping(bytes32 => uint256) answerHashToWeight;
        mapping(address => bytes32) registrantToAnswerHash;
        mapping(address => uint256) registrantToWeight;
    }

    constructor(IEigenLayrFeePayer _feePayer, IEigenLayrVoteWeigher _voteWeigher, string memory _explanation, uint256 _resolveTimeSinceLastVote) {
        feePayer = _feePayer;
        voteWeigher = _voteWeigher;
        explanation = _explanation;
        resolveTimeSinceLastVote = _resolveTimeSinceLastVote;
    }

    function initQuery(bytes calldata queryData) external returns (uint256) {
        feePayer.addQuery(nextQueryId++);
        queries[nextQueryId].startTime = block.timestamp;
        queries[nextQueryId].lastVoteTime = block.timestamp;
        return nextQueryId;
    }


    function voteOnNewAnswer(uint256 queryId, bytes calldata answerBytes) external returns (bytes32) {
        Query storage query = queries[queryId];
        require(query.startTime > 0 && query.lastVoteTime >= block.timestamp - resolveTimeSinceLastVote, "resolveTimeSinceLastVote has passed");
        require(query.registrantToWeight[msg.sender] == 0, "Registrant has already voted");
        uint256 weight = voteWeigher.weightOf(msg.sender);
        require(weight != 0, "This voter has no weight");
        bytes32 answerHash = sha256(answerBytes);
        query.answerHashToWeight[answerHash] += weight;
        query.registrantToAnswerHash[msg.sender] = answerHash;
        query.registrantToWeight[msg.sender] = weight;
    }

    function voteOnAnswer(uint256 queryId, bytes32 answerHash) external {
        Query storage query = queries[queryId];
        require(query.startTime > 0 && query.lastVoteTime >= block.timestamp - resolveTimeSinceLastVote, "resolveTimeSinceLastVote has passed");
        require(query.registrantToWeight[msg.sender] == 0, "Registrant has already voted");
        uint256 weight = voteWeigher.weightOf(msg.sender);
        require(weight != 0, "This voter has no weight");
        query.answerHashToWeight[answerHash] += weight;
        query.registrantToAnswerHash[msg.sender] = answerHash;
        query.registrantToWeight[msg.sender] = weight;
    }

    function resolveAnswer(uint256 queryId) external {
        Query storage query = queries[queryId];
        require(query.startTime > 0 && query.lastVoteTime <= block.timestamp - resolveTimeSinceLastVote, "resolveTimeSinceLastVote has passed");
        query.resolved = true;
    }
}
