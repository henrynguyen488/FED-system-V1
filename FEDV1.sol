// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FederalReserveSimulator {
    enum ProposalType {
        RateDecision,
        EmergencyFacility,
        BalanceSheetAction
    }

    enum ProposalStatus {
        Active,
        Approved,
        Rejected,
        Executed,
        Cancelled
    }

    struct ProposalCore {
        uint256 id;
        ProposalType proposalType;
        string title;
        string description;
        uint256 createdAt;
        uint256 deadline;
        ProposalStatus status;
        address proposer;
        bool executed;
    }

    struct ProposalVotes {
        uint256 yesVotes;
        uint256 noVotes;
    }

    struct RateProposal {
        uint256 proposedRateBps;
    }

    struct FacilityProposal {
        string facilityName;
        uint256 facilityLimit;
    }

    struct BalanceSheetProposal {
        string actionNote;
    }

    address public chair;
    uint256 public governorCount;
    uint256 public currentFederalFundsRateBps;

    bool public emergencyFacilityActive;
    string public activeFacilityName;
    uint256 public activeFacilityLimit;
    string public latestBalanceSheetAction;

    uint256 public proposalCount;

    mapping(address => bool) public isGovernor;

    mapping(uint256 => ProposalCore) public proposalCores;
    mapping(uint256 => ProposalVotes) public proposalVotes;
    mapping(uint256 => RateProposal) public rateProposals;
    mapping(uint256 => FacilityProposal) public facilityProposals;
    mapping(uint256 => BalanceSheetProposal) public balanceSheetProposals;

    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ChairTransferred(address indexed oldChair, address indexed newChair);
    event GovernorAdded(address indexed governor);
    event GovernorRemoved(address indexed governor);

    event ProposalCreated(
        uint256 indexed proposalId,
        ProposalType proposalType,
        address indexed proposer,
        string title,
        uint256 deadline
    );

    event Voted(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalApproved(uint256 indexed proposalId);
    event ProposalRejected(uint256 indexed proposalId);
    event ProposalExecuted(uint256 indexed proposalId);

    event RateUpdated(uint256 oldRateBps, uint256 newRateBps);
    event EmergencyFacilityOpened(string facilityName, uint256 facilityLimit);
    event EmergencyFacilityClosed(string facilityName);
    event BalanceSheetActionRecorded(string actionNote);

    modifier onlyChair() {
        require(msg.sender == chair, "Only chair");
        _;
    }

    modifier onlyGovernor() {
        require(isGovernor[msg.sender], "Only governor");
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(proposalId > 0 && proposalId <= proposalCount, "Invalid proposal id");
        _;
    }

    constructor(address[] memory initialGovernors, uint256 initialRateBps) {
        require(initialRateBps <= 10000, "Rate too high");

        chair = msg.sender;
        currentFederalFundsRateBps = initialRateBps;

        for (uint256 i = 0; i < initialGovernors.length; i++) {
            address governor = initialGovernors[i];

            require(governor != address(0), "Zero address governor");
            require(!isGovernor[governor], "Duplicate governor");

            isGovernor[governor] = true;
            governorCount++;

            emit GovernorAdded(governor);
        }

        if (!isGovernor[msg.sender]) {
            isGovernor[msg.sender] = true;
            governorCount++;

            emit GovernorAdded(msg.sender);
        }
    }

    // =========================
    // GOVERNANCE ADMIN
    // =========================

    function transferChair(address newChair) external onlyChair {
        require(newChair != address(0), "Zero address");

        address oldChair = chair;
        chair = newChair;

        if (!isGovernor[newChair]) {
            isGovernor[newChair] = true;
            governorCount++;

            emit GovernorAdded(newChair);
        }

        emit ChairTransferred(oldChair, newChair);
    }

    function addGovernor(address governor) external onlyChair {
        require(governor != address(0), "Zero address");
        require(!isGovernor[governor], "Already governor");

        isGovernor[governor] = true;
        governorCount++;

        emit GovernorAdded(governor);
    }

    function removeGovernor(address governor) external onlyChair {
        require(isGovernor[governor], "Not governor");
        require(governor != chair, "Cannot remove chair");

        isGovernor[governor] = false;
        governorCount--;

        emit GovernorRemoved(governor);
    }

    // =========================
    // INTERNAL CREATE HELPER
    // =========================

    function _createBaseProposal(
        ProposalType proposalType,
        string calldata title,
        string calldata description,
        uint256 votingPeriodSeconds
    ) internal returns (uint256) {
        require(votingPeriodSeconds > 0, "Invalid voting period");

        proposalCount++;
        uint256 proposalId = proposalCount;

        ProposalCore storage p = proposalCores[proposalId];

        p.id = proposalId;
        p.proposalType = proposalType;
        p.title = title;
        p.description = description;
        p.createdAt = block.timestamp;
        p.deadline = block.timestamp + votingPeriodSeconds;
        p.status = ProposalStatus.Active;
        p.proposer = msg.sender;

        emit ProposalCreated(
            proposalId,
            proposalType,
            msg.sender,
            title,
            p.deadline
        );

        return proposalId;
    }

    // =========================
    // CREATE PROPOSALS
    // =========================

    function createRateProposal(
        string calldata title,
        string calldata description,
        uint256 proposedRateBps,
        uint256 votingPeriodSeconds
    ) external onlyGovernor returns (uint256) {
        require(proposedRateBps <= 10000, "Rate too high");

        uint256 proposalId = _createBaseProposal(
            ProposalType.RateDecision,
            title,
            description,
            votingPeriodSeconds
        );

        rateProposals[proposalId] = RateProposal({
            proposedRateBps: proposedRateBps
        });

        return proposalId;
    }

    function createEmergencyFacilityProposal(
        string calldata title,
        string calldata description,
        string calldata facilityName,
        uint256 facilityLimit,
        uint256 votingPeriodSeconds
    ) external onlyGovernor returns (uint256) {
        require(bytes(facilityName).length > 0, "Facility name required");

        uint256 proposalId = _createBaseProposal(
            ProposalType.EmergencyFacility,
            title,
            description,
            votingPeriodSeconds
        );

        facilityProposals[proposalId] = FacilityProposal({
            facilityName: facilityName,
            facilityLimit: facilityLimit
        });

        return proposalId;
    }

    function createBalanceSheetProposal(
        string calldata title,
        string calldata description,
        string calldata actionNote,
        uint256 votingPeriodSeconds
    ) external onlyGovernor returns (uint256) {
        require(bytes(actionNote).length > 0, "Action note required");

        uint256 proposalId = _createBaseProposal(
            ProposalType.BalanceSheetAction,
            title,
            description,
            votingPeriodSeconds
        );

        balanceSheetProposals[proposalId] = BalanceSheetProposal({
            actionNote: actionNote
        });

        return proposalId;
    }

    // =========================
    // VOTING
    // =========================

    function vote(
        uint256 proposalId,
        bool support
    ) external onlyGovernor proposalExists(proposalId) {
        ProposalCore storage p = proposalCores[proposalId];

        require(p.status == ProposalStatus.Active, "Proposal not active");
        require(block.timestamp <= p.deadline, "Voting ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");

        hasVoted[proposalId][msg.sender] = true;

        ProposalVotes storage v = proposalVotes[proposalId];

        if (support) {
            v.yesVotes++;
        } else {
            v.noVotes++;
        }

        emit Voted(proposalId, msg.sender, support);
    }

    function finalizeProposal(
        uint256 proposalId
    ) external proposalExists(proposalId) {
        ProposalCore storage p = proposalCores[proposalId];
        ProposalVotes storage v = proposalVotes[proposalId];

        require(p.status == ProposalStatus.Active, "Proposal not active");
        require(block.timestamp > p.deadline, "Voting still ongoing");

        if (v.yesVotes > v.noVotes) {
            p.status = ProposalStatus.Approved;
            emit ProposalApproved(proposalId);
        } else {
            p.status = ProposalStatus.Rejected;
            emit ProposalRejected(proposalId);
        }
    }

    function executeProposal(
        uint256 proposalId
    ) external onlyChair proposalExists(proposalId) {
        ProposalCore storage p = proposalCores[proposalId];

        require(p.status == ProposalStatus.Approved, "Proposal not approved");
        require(!p.executed, "Already executed");

        p.executed = true;
        p.status = ProposalStatus.Executed;

        if (p.proposalType == ProposalType.RateDecision) {
            _executeRateProposal(proposalId);
        } else if (p.proposalType == ProposalType.EmergencyFacility) {
            _executeFacilityProposal(proposalId);
        } else if (p.proposalType == ProposalType.BalanceSheetAction) {
            _executeBalanceSheetProposal(proposalId);
        }

        emit ProposalExecuted(proposalId);
    }

    function _executeRateProposal(uint256 proposalId) internal {
        uint256 oldRate = currentFederalFundsRateBps;
        uint256 newRate = rateProposals[proposalId].proposedRateBps;

        currentFederalFundsRateBps = newRate;

        emit RateUpdated(oldRate, newRate);
    }

    function _executeFacilityProposal(uint256 proposalId) internal {
        FacilityProposal storage f = facilityProposals[proposalId];

        emergencyFacilityActive = true;
        activeFacilityName = f.facilityName;
        activeFacilityLimit = f.facilityLimit;

        emit EmergencyFacilityOpened(f.facilityName, f.facilityLimit);
    }

    function _executeBalanceSheetProposal(uint256 proposalId) internal {
        string storage actionNote = balanceSheetProposals[proposalId].actionNote;

        latestBalanceSheetAction = actionNote;

        emit BalanceSheetActionRecorded(actionNote);
    }

    function cancelProposal(
        uint256 proposalId
    ) external proposalExists(proposalId) {
        ProposalCore storage p = proposalCores[proposalId];

        require(msg.sender == chair || msg.sender == p.proposer, "Not authorized");
        require(p.status == ProposalStatus.Active, "Cannot cancel");

        p.status = ProposalStatus.Cancelled;
    }

    // =========================
    // EMERGENCY FACILITY CONTROL
    // =========================

    function closeEmergencyFacility() external onlyChair {
        require(emergencyFacilityActive, "No active facility");

        string memory oldName = activeFacilityName;

        emergencyFacilityActive = false;
        activeFacilityName = "";
        activeFacilityLimit = 0;

        emit EmergencyFacilityClosed(oldName);
    }

    // =========================
    // VIEW HELPERS
    // =========================

    function getProposalCore(
        uint256 proposalId
    ) external view proposalExists(proposalId) returns (ProposalCore memory) {
        return proposalCores[proposalId];
    }

    function getProposalVotes(
        uint256 proposalId
    ) external view proposalExists(proposalId) returns (ProposalVotes memory) {
        return proposalVotes[proposalId];
    }

    function getRateProposal(
        uint256 proposalId
    ) external view proposalExists(proposalId) returns (RateProposal memory) {
        return rateProposals[proposalId];
    }

    function getFacilityProposal(
        uint256 proposalId
    ) external view proposalExists(proposalId) returns (FacilityProposal memory) {
        return facilityProposals[proposalId];
    }

    function getBalanceSheetProposal(
        uint256 proposalId
    ) external view proposalExists(proposalId) returns (BalanceSheetProposal memory) {
        return balanceSheetProposals[proposalId];
    }

    function quorumReached(
        uint256 proposalId
    ) external view proposalExists(proposalId) returns (bool) {
        ProposalVotes storage v = proposalVotes[proposalId];

        uint256 totalVotes = v.yesVotes + v.noVotes;

        return totalVotes > governorCount / 2;
    }
}
["0x22c63cDcaC1EDD86ead1b794345411c181D97a5b","0x0744A7A8e4B6151483ec9c900eD2159aF89d51A4","0x9FB19Fc69b438cA3b328E2c85476E1A05686e862","0xcAf4c3053A61B5F53F4E7BAf3F5fE578D8C6458A","0xA319DeF2D663b7Cf41D9B68e538C6ABf746CA1b0","0xdEdb86D83886Ab364B60166AedB9Dacd78Eb1B19","0xF0615826C0bE06C196CE149495F29b1c3bC3F5A3"]