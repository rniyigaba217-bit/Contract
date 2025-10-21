// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract SchoolGradingSystem is AccessControl {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");
    bytes32 public constant STUDENT_ROLE = keccak256("STUDENT_ROLE");

    // Structs
    struct GradeRecord {
        uint256 score;
        uint256 maxScore;
        string assessmentType;
        uint256 timestamp;
    }

    struct Subject {
        string name;
        address teacher;
        uint256 creditHours;
        bool exists;
    }

    struct Student {
        string name;
        uint256 studentId;
        bool isActive;
    }

    struct Teacher {
        string name;
        uint256 teacherId;
        bool isActive;
    }

    struct StudentTranscript {
        uint256 totalCredits;
        uint256 totalGradePoints;
        string grade;
        uint256 lastUpdated;
    }

    // State variables
    mapping(address => Student) public students;
    mapping(address => Teacher) public teachers;
    mapping(uint256 => Subject) public subjects;
    mapping(address => mapping(uint256 => GradeRecord[])) private _studentGrades;
    mapping(address => StudentTranscript) public transcripts;
    mapping(address => mapping(uint256 => bool)) public isEnrolled;
    mapping(uint256 => address[]) private _subjectStudents; // Track students per subject for efficient iteration

    address[] public studentAddresses;
    uint256 public subjectCount;
    uint256 public academicYearStart;
    uint256 public academicYearEnd;
    uint256 public lastProcessedStudentIndex; // For batch processing

    // Events
    event GradeRecorded(address indexed student, uint256 subjectId, uint256 score, uint256 maxScore);
    event StudentEnrolled(address indexed student, uint256 subjectId);
    event TranscriptGenerated(address indexed student, string grade);
    event TranscriptBatchProcessed(uint256 fromIndex, uint256 toIndex);

    modifier onlyTeacher() {
        require(hasRole(TEACHER_ROLE, msg.sender), "Only teachers can perform this action");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Only admin can perform this action");
        _;
    }

    modifier onlyStudent() {
        require(hasRole(STUDENT_ROLE, msg.sender), "Only students can perform this action");
        _;
    }

    modifier withinAcademicYear() {
        require(block.timestamp >= academicYearStart && block.timestamp <= academicYearEnd, "Not within academic year");
        _;
    }

    constructor(uint256 _academicYearStart, uint256 _academicYearDuration) {
        _grantRole(ADMIN_ROLE, msg.sender);
        academicYearStart = _academicYearStart;
        academicYearEnd = _academicYearStart + _academicYearDuration;
    }

    // Admin functions
    function addTeacher(address _teacher, string memory _name, uint256 _teacherId) external onlyAdmin {
        require(!teachers[_teacher].isActive, "Teacher already exists");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(_teacherId > 0, "Teacher ID must be positive");

        teachers[_teacher] = Teacher({
            name: _name,
            teacherId: _teacherId,
            isActive: true
        });
        _grantRole(TEACHER_ROLE, _teacher);
    }

    function addStudent(address _student, string memory _name, uint256 _studentId) external onlyAdmin {
        require(!students[_student].isActive, "Student already exists");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(_studentId > 0, "Student ID must be positive");

        students[_student] = Student({
            name: _name,
            studentId: _studentId,
            isActive: true
        });
        studentAddresses.push(_student);
        _grantRole(STUDENT_ROLE, _student);
    }

    function addSubject(string memory _name, address _teacher, uint256 _creditHours) external onlyAdmin {
        require(teachers[_teacher].isActive, "Teacher not active");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(_creditHours > 0, "Credit hours must be positive");

        subjects[subjectCount] = Subject({
            name: _name,
            teacher: _teacher,
            creditHours: _creditHours,
            exists: true
        });
        subjectCount++;
    }

    function enrollStudent(address _student, uint256 _subjectId) external onlyAdmin {
        require(students[_student].isActive, "Student not active");
        require(_subjectId < subjectCount && subjects[_subjectId].exists, "Invalid subject ID");
        require(!isEnrolled[_student][_subjectId], "Student already enrolled");

        isEnrolled[_student][_subjectId] = true;
        _subjectStudents[_subjectId].push(_student);
        emit StudentEnrolled(_student, _subjectId);
    }

    // Teacher functions
    function recordGrade(
        address _student,
        uint256 _subjectId,
        uint256 _score,
        uint256 _maxScore,
        string memory _assessmentType
    )
        external
        onlyTeacher
        withinAcademicYear
    {
        require(isEnrolled[_student][_subjectId], "Student not enrolled");
        require(subjects[_subjectId].teacher == msg.sender, "Only subject teacher can record grades");
        require(_score <= _maxScore, "Score cannot exceed max score");
        require(_maxScore > 0, "Max score must be positive");
        require(bytes(_assessmentType).length > 0, "Assessment type cannot be empty");

        _studentGrades[_student][_subjectId].push(GradeRecord({
            score: _score,
            maxScore: _maxScore,
            assessmentType: _assessmentType,
            timestamp: block.timestamp
        }));

        emit GradeRecorded(_student, _subjectId, _score, _maxScore);
    }

    // Student functions
    function viewGrades(uint256 _subjectId) external onlyStudent view returns (GradeRecord[] memory) {
        return _studentGrades[msg.sender][_subjectId];
    }

    function viewTranscript() external onlyStudent view returns (StudentTranscript memory) {
        return transcripts[msg.sender];
    }

    // Admin functions for transcript generation
    function generateTranscriptsBatch(uint256 batchSize) external onlyAdmin {
        require(block.timestamp >= academicYearEnd, "Academic year not ended");
        require(lastProcessedStudentIndex + batchSize <= studentAddresses.length, "Batch size too large");

        uint256 endIndex = lastProcessedStudentIndex + batchSize;

        for (uint256 i = lastProcessedStudentIndex; i < endIndex; i++) {
            address student = studentAddresses[i];
            if (students[student].isActive) {
                _generateTranscriptForStudent(student);
            }
        }

        lastProcessedStudentIndex = endIndex;
        emit TranscriptBatchProcessed(lastProcessedStudentIndex - batchSize, endIndex - 1);
    }

    function _generateTranscriptForStudent(address _student) private {
        uint256 totalGradePoints;
        uint256 totalCredits;

        for (uint256 j = 0; j < subjectCount; j++) {
            if (isEnrolled[_student][j]) {
                GradeRecord[] memory grades = _studentGrades[_student][j];
                if (grades.length > 0) {
                    uint256 totalScore;
                    uint256 totalMaxScore;

                    for (uint256 k = 0; k < grades.length; k++) {
                        totalScore += grades[k].score;
                        totalMaxScore += grades[k].maxScore;
                    }

                    uint256 percentage = (totalScore * 100) / totalMaxScore;
                    uint256 gradePoints = _calculateGradePoints(percentage);

                    totalGradePoints += gradePoints * subjects[j].creditHours;
                    totalCredits += subjects[j].creditHours;
                }
            }
        }

        if (totalCredits > 0) {
            string memory finalGrade = _determineFinalGrade(totalGradePoints / totalCredits);

            transcripts[_student] = StudentTranscript({
                totalCredits: totalCredits,
                totalGradePoints: totalGradePoints,
                grade: finalGrade,
                lastUpdated: block.timestamp
            });

            emit TranscriptGenerated(_student, finalGrade);
        }
    }

    // Helper functions
    function _calculateGradePoints(uint256 percentage) internal pure returns (uint256) {
        if (percentage >= 90) return 4;
        else if (percentage >= 80) return 3;
        else if (percentage >= 70) return 2;
        else if (percentage >= 60) return 1;
        else return 0;
    }

    function _determineFinalGrade(uint256 gpa) internal pure returns (string memory) {
        if (gpa == 4) return "A";
        else if (gpa >= 3) return "B";
        else if (gpa >= 2) return "C";
        else if (gpa >= 1) return "D";
        else return "F";
    }

    // Getter functions
    function getSubjectCount() external view returns (uint256) {
        return subjectCount;
    }

    function getStudentGrades(address _student, uint256 _subjectId) external view returns (GradeRecord[] memory) {
        return _studentGrades[_student][_subjectId];
    }

    function getStudentTranscript(address _student) external view returns (StudentTranscript memory) {
        return transcripts[_student];
    }

    function getSubjectStudents(uint256 _subjectId) external view returns (address[] memory) {
        return _subjectStudents[_subjectId];
    }
}
