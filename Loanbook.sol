// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/v4.9.6/contracts/access/OwnableUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/v4.9.6/contracts/access/AccessControlUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/v4.9.6/contracts/utils/structs/EnumerableSetUpgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/v4.9.6/contracts/token/ERC20/IERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/v4.9.6/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/v4.9.6/contracts/proxy/utils/Initializable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/v4.9.6/contracts/proxy/utils/UUPSUpgradeable.sol";

contract LoanBook is
    Initializable,
    OwnableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct LoanRequest {
        uint256 requestedAmount;
        uint256 repaidAmount;
    }

    struct Group {
        EnumerableSetUpgradeable.AddressSet members;
        address manager;
        bool isOpen;
        IERC20Upgradeable token;
        uint256 availableFunding;
        mapping(address => LoanRequest[]) loanRequests;
        mapping(address => uint256) loansToUser;
    }

    mapping(uint256 => Group) private groups;
    mapping(address => uint256) public userOnGroup;
    uint256 public groupIdCounter;

    bytes32 public constant ADMIN_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    event GroupCreated(
        uint256 indexed groupId,
        address indexed manager,
        address tokenAddress
    );
    event GroupClosed(uint256 indexed groupId);
    event MemberAdded(uint256 indexed groupId, address indexed member);
    event MemberRemoved(uint256 indexed groupId, address indexed member);
    event MembersAdded(uint256 indexed groupId, address[] members);
    event MembersRemoved(uint256 indexed groupId, address[] members);
    event GroupFunded(
        uint256 indexed groupId,
        address indexed funder,
        uint256 amount
    );
    event LoanRequested(
        uint256 indexed groupId,
        address indexed borrower,
        uint256 loanId,
        uint256 amount
    );
    event LoanRepaid(
        uint256 indexed groupId,
        address indexed borrower,
        uint256 loanId,
        uint256 amount
    );
    event ManagerChanged(
        uint256 indexed groupId,
        address indexed oldManager,
        address indexed newManager
    );

    function initialize() public initializer {
        __Ownable_init();
        __AccessControl_init();
        _setRoleAdmin(MANAGER_ROLE, ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        groupIdCounter = 1; // Initialize counter
    }

    function getGroup(uint256 _groupId)
        external
        view
        returns (
            address,
            uint256,
            IERC20Upgradeable,
            bool,
            uint256
        )
    {
        Group storage group = groups[_groupId];
        return (
            group.manager,
            group.availableFunding,
            group.token,
            group.isOpen,
            group.members.length()
        );
    }

    function getGroupMember(uint256 _groupId, uint256 _index)
        external
        view
        returns (address)
    {
        return groups[_groupId].members.at(_index);
    }

    function getMemberLoansCount(uint256 _groupId, address _member)
        external
        view
        returns (uint256)
    {
        return groups[_groupId].loansToUser[_member];
    }

    function getMemberLoanRequest(
        uint256 _groupId,
        address _member,
        uint256 _index
    ) external view returns (LoanRequest memory) {
        return groups[_groupId].loanRequests[_member][_index];
    }

    function createGroup(address _manager, address _tokenAddress)
        public
        onlyOwner
    {
        uint256 groupId = groupIdCounter++;
        Group storage group = groups[groupId];
        group.isOpen = true;
        group.manager = _manager;
        group.members.add(_manager);
        group.token = IERC20Upgradeable(_tokenAddress);
        grantRole(MANAGER_ROLE, _manager);
        userOnGroup[_manager] = groupId;
        emit GroupCreated(groupId, _manager, _tokenAddress);
    }

    function closeGroup(uint256 _groupId) external onlyOwner {
        require(groups[_groupId].isOpen, "Group is already closed");
        groups[_groupId].isOpen = false;
        emit GroupClosed(_groupId);
    }

    function addMember(uint256 _groupId, address _member) external {
        require(
            hasRole(MANAGER_ROLE, msg.sender) || owner() == msg.sender,
            "Not authorized"
        );
        require(groups[_groupId].isOpen, "Group is closed");
        groups[_groupId].members.add(_member);
        userOnGroup[_member] = _groupId;
        emit MemberAdded(_groupId, _member);
    }

    function removeMember(uint256 _groupId, address _member) external {
        require(
            hasRole(MANAGER_ROLE, msg.sender) || owner() == msg.sender,
            "Not authorized"
        );
        require(groups[_groupId].isOpen, "Group is closed");
        groups[_groupId].members.remove(_member);
        emit MemberRemoved(_groupId, _member);
    }

    function addMembers(uint256 _groupId, address[] memory _members) external {
        require(
            hasRole(MANAGER_ROLE, msg.sender) || owner() == msg.sender,
            "Not authorized"
        );
        require(groups[_groupId].isOpen, "Group is closed");
        for (uint256 i = 0; i < _members.length; i++) {
            groups[_groupId].members.add(_members[i]);
        }
        emit MembersAdded(_groupId, _members);
    }

    function removeMembers(uint256 _groupId, address[] memory _members)
        external
    {
        require(
            hasRole(MANAGER_ROLE, msg.sender) || owner() == msg.sender,
            "Not authorized"
        );
        require(groups[_groupId].isOpen, "Group is closed");
        for (uint256 i = 0; i < _members.length; i++) {
            groups[_groupId].members.remove(_members[i]);
        }
        emit MembersRemoved(_groupId, _members);
    }


    function fundGroup(uint256 _groupId, uint256 _amount) external onlyOwner {
        require(groups[_groupId].isOpen, "Group is closed");
        require(groups[_groupId].token.balanceOf(address(this)) >= _amount, "Insufficient balance on contract");
        groups[_groupId].availableFunding += _amount;
        emit GroupFunded(_groupId, msg.sender, _amount);
    }

    function requestLoan(uint256 _groupId, uint256 _amount) external onlyOwner {
        require(
            groups[_groupId].members.contains(msg.sender),
            "Not a group member"
        );
        require(groups[_groupId].isOpen, "Group is closed");
        require(
            _amount <= groups[_groupId].availableFunding,
            "Requested amount exceeds available funding"
        );
        uint256 loanId = groups[_groupId].loanRequests[msg.sender].length;
        groups[_groupId].token.safeTransfer(msg.sender, _amount);
        groups[_groupId].loanRequests[msg.sender].push(LoanRequest(_amount, 0));
        groups[_groupId].loansToUser[msg.sender]++;
        groups[_groupId].availableFunding -= _amount;
        emit LoanRequested(_groupId, msg.sender, loanId, _amount);
    }

    function repayLoan(
        uint256 _groupId,
        uint256 _loanId,
        uint256 _amount
    ) external {
        require(groups[_groupId].isOpen, "Group is closed");
        require(
            groups[_groupId].members.contains(msg.sender),
            "Not a group member"
        );
        require(
            _loanId < groups[_groupId].loanRequests[msg.sender].length,
            "Invalid loan ID"
        );
        groups[_groupId].token.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        groups[_groupId]
        .loanRequests[msg.sender][_loanId].repaidAmount += _amount;
        groups[_groupId].availableFunding += _amount;
        emit LoanRepaid(_groupId, msg.sender, _loanId, _amount);
    }

    function changeManager(uint256 _groupId, address _newManager)
        external
        onlyOwner
    {
        require(groups[_groupId].isOpen, "Group is closed");
        address oldManager = groups[_groupId].manager;
        groups[_groupId].manager = _newManager;
        _grantRole(MANAGER_ROLE, _newManager);
        _revokeRole(MANAGER_ROLE, oldManager);
        emit ManagerChanged(_groupId, oldManager, _newManager);
    }

    function sendERC20(
        address _tokenAddress,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        IERC20Upgradeable token = IERC20Upgradeable(_tokenAddress);
        token.safeTransfer(_to, _amount);
    }

    modifier onlyOwnerOrManager(uint256 _groupId) {
        require(
            owner() == msg.sender || groups[_groupId].manager == msg.sender,
            "Not authorized"
        );
        _;
    }

    modifier onlyGroupMember(uint256 _groupId) {
        require(
            groups[_groupId].members.contains(msg.sender),
            "Not a group member"
        );
        _;
    }

    /*
    _________________________________________________________________________________________________

    UUPS UPGRADE, AND ROLE HELPERS
    _________________________________________________________________________________________________
    */

    // Override _authorizeUpgrade function required by UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // Grant roles helper
    function grantAdminRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(ADMIN_ROLE, account);
    }

    function grantUpgraderRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(UPGRADER_ROLE, account);
    }

    // Revoke roles helper
    function revokeAdminRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(ADMIN_ROLE, account);
    }

    function revokeUpgraderRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(UPGRADER_ROLE, account);
    }

    // Override transferOwnership to also manage roles
    function transferOwnership(address newOwner) public override onlyOwner {
        address oldOwner = owner();

        // Transfer ownership
        super.transferOwnership(newOwner);

        // Grant roles to the new owner
        _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
        _setupRole(UPGRADER_ROLE, newOwner);

        // Revoke roles from the old owner
        _revokeRole(DEFAULT_ADMIN_ROLE, oldOwner);
        _revokeRole(UPGRADER_ROLE, oldOwner);
    }
}