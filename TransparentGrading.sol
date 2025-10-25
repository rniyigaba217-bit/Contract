// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TransparentGradingWithResits
 * @dev Records student grading attempts immutably and supports a controlled resit mechanism.
 *      Demo mode: requires only 1 approver (minApprovals = 1).
 */

contract TransparentGradingWithResits {
    address public ministry;              // main admin (e.g., Ministry of Education)
    uint public minApprovals = 1;         // demo: approvals required for a resit

    // roles
    mapping(address => bool) public teachers;   // teacher accounts permitted to record initial attempts
    mapping(address => bool) public approvers;  // accounts that can approve resits (e.g., headteacher, ministry rep)

    // Student attempt (immutable once pushed)
    struct Attempt {
        uint256 testScore;
        uint256 examScore;
        uint256 finalGrade;
        uint256 timestamp;
        string note;
    }

    // Resit request record
    struct Resit {
        uint id;
        address student;
        string reason;
        uint256 requestedAt;
        bool resolved;         // true when approvals reached
        bool executed;         // true after a resit result has been submitted
        uint approvalsCount;
    }

    // storage
    mapping(address => Attempt[]) private history;   // student => list of attempts
    mapping(uint => Resit) public resits;            // resitId => Resit
    mapping(uint => mapping(address => bool)) public resitApprovals; // resitId => approver => approved

    // track resits per student and states
    mapping(address => uint[]) public studentResitIds; // student => list of resit ids
    mapping(address => bool) public hasPendingResit;  // student => true if student currently has a pending (unresolved) resit
    mapping(address => bool) public hasResitted;      // student => true if student already completed a resit

    uint public resitCounter;

    // Events
    event TeacherAdded(address indexed teacher);
    event ApproverAdded(address indexed approver);
    event AttemptRecorded(address indexed student, uint indexed attemptIndex, uint256 finalGrade, string note);
    event ResitRequested(uint indexed resitId, address indexed student, string reason);
    event ResitApproved(uint indexed resitId, address indexed approver, uint approvalsCount);
    event ResitResolved(uint indexed resitId, address indexed student);
    event ResitExecuted(uint indexed resitId, address indexed student, uint256 finalGrade, string note);
    event MinApprovalsChanged(uint newMinApprovals);

    // modifiers
    modifier onlyMinistry() {
        require(msg.sender == ministry, "Only ministry");
        _;
    }
    modifier onlyTeacherOrMinistry() {
        require(msg.sender == ministry || teachers[msg.sender], "Only teacher or ministry");
        _;
    }
    modifier onlyApprover() {
        require(approvers[msg.sender] || msg.sender == ministry, "Only approver or ministry");
        _;
    }

    constructor() {
        ministry = msg.sender;
        approvers[msg.sender] = true; // ministry is an approver by default
    }

    // -----------------------
    // Role management
    // -----------------------
    function addTeacher(address _teacher) external onlyMinistry {
        teachers[_teacher] = true;
        emit TeacherAdded(_teacher);
    }

    function addApprover(address _approver) external onlyMinistry {
        approvers[_approver] = true;
        emit ApproverAdded(_approver);
    }

    function setMinApprovals(uint _min) external onlyMinistry {
        require(_min >= 1, "min must be >= 1");
        minApprovals = _min;
        emit MinApprovalsChanged(_min);
    }

    // -----------------------
    // Record an initial attempt
    // -----------------------
    function recordInitialAttempt(address _student, uint256 _testScore, uint256 _examScore, string calldata _note)
        external
        onlyTeacherOrMinistry
    {
        uint256 finalGrade = _computeFinal(_testScore, _examScore);
        Attempt memory a = Attempt({
            testScore: _testScore,
            examScore: _examScore,
            finalGrade: finalGrade,
            timestamp: block.timestamp,
            note: _note
        });

        history[_student].push(a);
        uint attemptIndex = history[_student].length - 1;
        emit AttemptRecorded(_student, attemptIndex, finalGrade, _note);
    }

    // -----------------------
    // Resit flow
    // -----------------------
    function requestResit(address _student, string calldata _reason) external {
        require(!hasPendingResit[_student], "Student already has a pending resit request.");
        require(!hasResitted[_student], "Student already completed a resit before.");

        resitCounter++;
        uint id = resitCounter;
        resits[id] = Resit({
            id: id,
            student: _student,
            reason: _reason,
            requestedAt: block.timestamp,
            resolved: false,
            executed: false,
            approvalsCount: 0
        });

        studentResitIds[_student].push(id);
        hasPendingResit[_student] = true;

        emit ResitRequested(id, _student, _reason);
    }

    function approveResit(uint _resitId) external onlyApprover {
        require(resits[_resitId].id != 0, "Resit not exist");
        require(!resits[_resitId].resolved, "Resit already resolved");
        require(!resitApprovals[_resitId][msg.sender], "Already approved");

        resitApprovals[_resitId][msg.sender] = true;
        resits[_resitId].approvalsCount++;

        emit ResitApproved(_resitId, msg.sender, resits[_resitId].approvalsCount);

        // if approvals reached, mark resolved and emit
        if (resits[_resitId].approvalsCount >= minApprovals) {
            resits[_resitId].resolved = true;
            emit ResitResolved(_resitId, resits[_resitId].student);
        }
    }

    function submitResitResult(uint _resitId, uint256 _testScore, uint256 _examScore, string calldata _note)
        external
        onlyTeacherOrMinistry
    {
        Resit storage r = resits[_resitId];
        require(r.id != 0, "Resit not exist");
        require(r.resolved, "Resit not approved yet");
        require(!r.executed, "Resit already executed");

        uint256 finalGrade = _computeFinal(_testScore, _examScore);
        Attempt memory a = Attempt({
            testScore: _testScore,
            examScore: _examScore,
            finalGrade: finalGrade,
            timestamp: block.timestamp,
            note: _note
        });

        history[r.student].push(a);
        uint attemptIndex = history[r.student].length - 1;

        r.executed = true;
        hasPendingResit[r.student] = false;
        hasResitted[r.student] = true;

        emit ResitExecuted(_resitId, r.student, finalGrade, _note);
        emit AttemptRecorded(r.student, attemptIndex, finalGrade, _note);
    }

    // -----------------------
    // View helpers
    // -----------------------
    function getAttemptCount(address _student) external view returns (uint) {
        return history[_student].length;
    }

    function getAttempt(address _student, uint _index)
        external
        view
        returns (uint256 testScore, uint256 examScore, uint256 finalGrade, uint256 timestamp, string memory note)
    {
        require(_index < history[_student].length, "No such attempt");
        Attempt storage a = history[_student][_index];
        return (a.testScore, a.examScore, a.finalGrade, a.timestamp, a.note);
    }

    function getAllAttempts(address _student) external view returns (Attempt[] memory) {
        return history[_student];
    }

    function getResitsByStudent(address _student) external view returns (uint[] memory) {
        return studentResitIds[_student];
    }

    function getResitDetails(uint _resitId) external view returns (
        uint id,
        address student,
        string memory reason,
        uint256 requestedAt,
        bool resolved,
        bool executed,
        uint approvalsCount
    ) {
        Resit storage r = resits[_resitId];
        return (r.id, r.student, r.reason, r.requestedAt, r.resolved, r.executed, r.approvalsCount);
    }

    function getLatestResitIdForStudent(address _student) external view returns (uint) {
        uint[] storage ids = studentResitIds[_student];
        if (ids.length == 0) return 0;
        return ids[ids.length - 1];
    }

    // -----------------------
    // Internal utilities
    // -----------------------
    function _computeFinal(uint256 _test, uint256 _exam) internal pure returns (uint256) {
        return (_test * 40 + _exam * 60) / 100;
    }
}
