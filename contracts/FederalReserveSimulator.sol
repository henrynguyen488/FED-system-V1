// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FederalReserveSimulator
 * @notice A governance system simulating Federal Reserve decision-making.
 *         FOMC members can propose rate changes, emergency lending facilities,
 *         and balance-sheet actions, then vote, finalize, and execute them.
 */
contract FederalReserveSimulator {
    // ─── Enumerations ────────────────────────────────────────────────────────

    /// @notice The category of a governance proposal.
    enum ProposalType {
        RateChange,          // Adjust the federal-funds target rate (basis points)
        EmergencyFacility,   // Activate an emergency lending facility ($ millions)
        BalanceSheetAction   // Expand or shrink the Fed balance sheet ($ millions)
    }

    /// @notice Lifecycle state of a proposal.
    enum ProposalStatus {
        Pending,   // Voting in progress
        Approved,  // Passed quorum & majority, awaiting execution
        Rejected,  // Failed quorum or majority
        Executed   // Policy change applied on-chain
    }

    // ─── Data structures ─────────────────────────────────────────────────────

    struct Proposal {
        uint256 id;
        ProposalType proposalType;
        string description;
        /// @dev For RateChange: signed delta in basis points (e.g. 25 = +0.25 %).
        int256 rateChangeBps;
        /// @dev For EmergencyFacility: facility size in $ millions.
        uint256 facilityAmountM;
        /// @dev For BalanceSheetAction: signed delta in $ millions.
        int256 balanceSheetDeltaM;
        uint256 votesFor;
        uint256 votesAgainst;
        ProposalStatus status;
        uint256 createdAt;
        uint256 deadline;
        address proposer;
        bool finalized;
        bool executed;
    }

    // ─── State variables ─────────────────────────────────────────────────────

    /// @notice Current federal-funds target rate in basis points (e.g. 525 = 5.25 %).
    uint256 public federalFundsRate;

    /// @notice Total Fed balance sheet in $ millions (e.g. 8_000_000 = $8 trillion).
    uint256 public totalBalanceSheetM;

    /// @notice Cumulative emergency-facility commitments in $ millions.
    uint256 public emergencyFacilityTotalM;

    /// @notice Total number of proposals ever created.
    uint256 public proposalCount;

    /// @notice Minimum total votes required for a proposal to reach quorum.
    uint256 public quorumThreshold;

    /// @notice Voting window in seconds after a proposal is created.
    uint256 public votingPeriod;

    /// @notice Address of the FOMC Chair (deployer), can add members.
    address public chair;

    mapping(uint256 => Proposal) private _proposals;
    mapping(uint256 => mapping(address => bool)) private _hasVoted;
    mapping(address => bool) public isMember;
    address[] private _members;

    // ─── Events ──────────────────────────────────────────────────────────────

    event MemberAdded(address indexed member);
    event ProposalCreated(
        uint256 indexed id,
        ProposalType proposalType,
        string description,
        address indexed proposer
    );
    event Voted(uint256 indexed id, address indexed voter, bool support);
    event ProposalFinalized(uint256 indexed id, ProposalStatus status);
    event ProposalExecuted(uint256 indexed id);
    event RateChanged(uint256 oldRateBps, uint256 newRateBps);
    event BalanceSheetChanged(uint256 oldAmountM, uint256 newAmountM);
    event EmergencyFacilityActivated(uint256 indexed proposalId, uint256 amountM);

    // ─── Modifiers ───────────────────────────────────────────────────────────

    modifier onlyMember() {
        require(isMember[msg.sender], "FRS: caller is not an FOMC member");
        _;
    }

    modifier onlyChair() {
        require(msg.sender == chair, "FRS: caller is not the Chair");
        _;
    }

    modifier proposalExists(uint256 id) {
        require(id > 0 && id <= proposalCount, "FRS: proposal does not exist");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    /**
     * @param initialRateBps   Starting federal-funds rate in basis points.
     * @param initialBalanceM  Starting balance sheet in $ millions.
     * @param _quorumThreshold Minimum votes required for quorum.
     * @param _votingPeriod    Voting window in seconds.
     */
    constructor(
        uint256 initialRateBps,
        uint256 initialBalanceM,
        uint256 _quorumThreshold,
        uint256 _votingPeriod
    ) {
        chair = msg.sender;
        federalFundsRate = initialRateBps;
        totalBalanceSheetM = initialBalanceM;
        quorumThreshold = _quorumThreshold;
        votingPeriod = _votingPeriod;

        // Chair is automatically the first FOMC member.
        isMember[msg.sender] = true;
        _members.push(msg.sender);
        emit MemberAdded(msg.sender);
    }

    // ─── Membership ──────────────────────────────────────────────────────────

    /**
     * @notice Add a new FOMC member. Only the Chair may call this.
     * @param member Address of the new member.
     */
    function addMember(address member) external onlyChair {
        require(member != address(0), "FRS: zero address");
        require(!isMember[member], "FRS: already a member");
        isMember[member] = true;
        _members.push(member);
        emit MemberAdded(member);
    }

    // ─── Proposal lifecycle ──────────────────────────────────────────────────

    /**
     * @notice Create a new governance proposal.
     * @param proposalType       Category of the action.
     * @param description        Human-readable rationale.
     * @param rateChangeBps      (RateChange only) Signed delta in basis points.
     * @param facilityAmountM    (EmergencyFacility only) Facility size in $ millions.
     * @param balanceSheetDeltaM (BalanceSheetAction only) Signed delta in $ millions.
     * @return id The new proposal's numeric identifier.
     */
    function createProposal(
        ProposalType proposalType,
        string calldata description,
        int256 rateChangeBps,
        uint256 facilityAmountM,
        int256 balanceSheetDeltaM
    ) external onlyMember returns (uint256 id) {
        require(bytes(description).length > 0, "FRS: empty description");

        proposalCount++;
        id = proposalCount;

        _proposals[id] = Proposal({
            id: id,
            proposalType: proposalType,
            description: description,
            rateChangeBps: rateChangeBps,
            facilityAmountM: facilityAmountM,
            balanceSheetDeltaM: balanceSheetDeltaM,
            votesFor: 0,
            votesAgainst: 0,
            status: ProposalStatus.Pending,
            createdAt: block.timestamp,
            deadline: block.timestamp + votingPeriod,
            proposer: msg.sender,
            finalized: false,
            executed: false
        });

        emit ProposalCreated(id, proposalType, description, msg.sender);
    }

    /**
     * @notice Cast a vote on an open proposal.
     * @param proposalId Proposal to vote on.
     * @param support    True = vote for; false = vote against.
     */
    function vote(uint256 proposalId, bool support)
        external
        onlyMember
        proposalExists(proposalId)
    {
        Proposal storage p = _proposals[proposalId];
        require(!p.finalized, "FRS: proposal already finalized");
        require(block.timestamp <= p.deadline, "FRS: voting period has ended");
        require(!_hasVoted[proposalId][msg.sender], "FRS: already voted");

        _hasVoted[proposalId][msg.sender] = true;
        if (support) {
            p.votesFor++;
        } else {
            p.votesAgainst++;
        }
        emit Voted(proposalId, msg.sender, support);
    }

    /**
     * @notice Finalize a proposal after its voting period has closed.
     *         Sets the status to Approved or Rejected.
     * @param proposalId Proposal to finalize.
     */
    function finalize(uint256 proposalId)
        external
        onlyMember
        proposalExists(proposalId)
    {
        Proposal storage p = _proposals[proposalId];
        require(!p.finalized, "FRS: already finalized");
        require(block.timestamp > p.deadline, "FRS: voting period still open");

        p.finalized = true;
        uint256 totalVotes = p.votesFor + p.votesAgainst;

        if (totalVotes >= quorumThreshold && p.votesFor > p.votesAgainst) {
            p.status = ProposalStatus.Approved;
        } else {
            p.status = ProposalStatus.Rejected;
        }

        emit ProposalFinalized(proposalId, p.status);
    }

    /**
     * @notice Execute an approved proposal and apply the policy change.
     * @param proposalId Proposal to execute.
     */
    function execute(uint256 proposalId)
        external
        onlyMember
        proposalExists(proposalId)
    {
        Proposal storage p = _proposals[proposalId];
        require(p.finalized, "FRS: not yet finalized");
        require(p.status == ProposalStatus.Approved, "FRS: proposal not approved");
        require(!p.executed, "FRS: already executed");

        p.executed = true;
        p.status = ProposalStatus.Executed;

        if (p.proposalType == ProposalType.RateChange) {
            uint256 oldRate = federalFundsRate;
            if (p.rateChangeBps >= 0) {
                federalFundsRate += uint256(p.rateChangeBps);
            } else {
                uint256 decrease = uint256(-p.rateChangeBps);
                federalFundsRate = federalFundsRate >= decrease
                    ? federalFundsRate - decrease
                    : 0;
            }
            emit RateChanged(oldRate, federalFundsRate);

        } else if (p.proposalType == ProposalType.EmergencyFacility) {
            emergencyFacilityTotalM += p.facilityAmountM;
            uint256 oldBalance = totalBalanceSheetM;
            totalBalanceSheetM += p.facilityAmountM;
            emit EmergencyFacilityActivated(proposalId, p.facilityAmountM);
            emit BalanceSheetChanged(oldBalance, totalBalanceSheetM);

        } else if (p.proposalType == ProposalType.BalanceSheetAction) {
            uint256 oldBalance = totalBalanceSheetM;
            if (p.balanceSheetDeltaM >= 0) {
                totalBalanceSheetM += uint256(p.balanceSheetDeltaM);
            } else {
                uint256 decrease = uint256(-p.balanceSheetDeltaM);
                totalBalanceSheetM = totalBalanceSheetM >= decrease
                    ? totalBalanceSheetM - decrease
                    : 0;
            }
            emit BalanceSheetChanged(oldBalance, totalBalanceSheetM);
        }

        emit ProposalExecuted(proposalId);
    }

    // ─── View functions ──────────────────────────────────────────────────────

    /**
     * @notice Retrieve a proposal by ID.
     */
    function getProposal(uint256 id)
        external
        view
        proposalExists(id)
        returns (Proposal memory)
    {
        return _proposals[id];
    }

    /**
     * @notice Check whether a given address has already voted on a proposal.
     */
    function hasVotedOnProposal(uint256 proposalId, address voter)
        external
        view
        returns (bool)
    {
        return _hasVoted[proposalId][voter];
    }

    /**
     * @notice Return the number of FOMC members.
     */
    function getMemberCount() external view returns (uint256) {
        return _members.length;
    }

    /**
     * @notice Return the address of FOMC member at a given index.
     */
    function getMember(uint256 index) external view returns (address) {
        require(index < _members.length, "FRS: index out of range");
        return _members[index];
    }

    /**
     * @notice Return a snapshot of the core contract state in a single call.
     * @return rateBps            Current federal-funds rate in basis points.
     * @return balanceSheetM      Total balance sheet in $ millions.
     * @return facilityM          Cumulative emergency facilities in $ millions.
     * @return totalProposals     Total proposals created.
     * @return memberCount        Number of FOMC members.
     * @return chairAddress       Address of the FOMC Chair.
     * @return currentQuorum      Current quorum threshold.
     * @return currentVotingPeriod Current voting period in seconds.
     */
    function getContractState()
        external
        view
        returns (
            uint256 rateBps,
            uint256 balanceSheetM,
            uint256 facilityM,
            uint256 totalProposals,
            uint256 memberCount,
            address chairAddress,
            uint256 currentQuorum,
            uint256 currentVotingPeriod
        )
    {
        return (
            federalFundsRate,
            totalBalanceSheetM,
            emergencyFacilityTotalM,
            proposalCount,
            _members.length,
            chair,
            quorumThreshold,
            votingPeriod
        );
    }
}
