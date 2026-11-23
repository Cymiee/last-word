// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Last Word: a tamper-proof will registry
/// @notice Notaries file the SHA-256 fingerprint of a will document, never its content.
///         Amendments are appended as new versions; nothing is ever edited or deleted.
///         Once a death is recorded for a will, no further versions can be filed.
/// @dev All reads are plain view calls, so anyone can verify a document without a wallet.
contract LastWord {
    /// @notice One filed version of a will.
    /// @param docHash SHA-256 hash of the will document.
    /// @param filedAt Block timestamp when this version was filed.
    /// @param notary Address of the notary who filed it.
    struct Version {
        bytes32 docHash;
        uint64 filedAt;
        address notary;
    }

    /// @notice The registry operator. Approves notaries and records deaths.
    address public immutable admin;

    mapping(address => bool) private _notaries;
    mapping(string => Version[]) private _versions;
    mapping(string => uint64) private _deceasedAt;

    error NotAdmin();
    error NotANotary();
    error TestatorDeceased(uint64 at);
    error AlreadyDeceased();
    error NoWillFiled();
    error EmptyHash();
    error DuplicateVersion();

    event NotaryAdded(address indexed notary);
    event NotaryRemoved(address indexed notary);
    event WillFiled(string willId, uint256 version, bytes32 docHash, address indexed notary);
    event DeathRecorded(string willId, bytes32 certHash);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyNotary() {
        if (!_notaries[msg.sender]) revert NotANotary();
        _;
    }

    /// @notice Deploys the registry with the deployer as admin.
    constructor() {
        admin = msg.sender;
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    /// @notice Approves an address to file wills.
    /// @param notary The address to approve.
    function addNotary(address notary) external onlyAdmin {
        _notaries[notary] = true;
        emit NotaryAdded(notary);
    }

    /// @notice Revokes a notary's right to file wills. Versions they already filed stay on record.
    /// @param notary The address to revoke.
    function removeNotary(address notary) external onlyAdmin {
        _notaries[notary] = false;
        emit NotaryRemoved(notary);
    }

    /// @notice Records the testator's death, which permanently closes the will to new versions.
    /// @param willId The will identifier, e.g. "T-001".
    /// @param certHash SHA-256 hash of the death certificate.
    function recordDeath(string calldata willId, bytes32 certHash) external onlyAdmin {
        if (certHash == bytes32(0)) revert EmptyHash();
        if (_versions[willId].length == 0) revert NoWillFiled();
        if (_deceasedAt[willId] != 0) revert AlreadyDeceased();

        _deceasedAt[willId] = uint64(block.timestamp);
        emit DeathRecorded(willId, certHash);
    }

    // ---------------------------------------------------------------------
    // Notary
    // ---------------------------------------------------------------------

    /// @notice Files a new will, or a new version (amendment) of an existing one.
    /// @param willId The will identifier, e.g. "T-001".
    /// @param docHash SHA-256 hash of the will document.
    function fileWill(string calldata willId, bytes32 docHash) external onlyNotary {
        uint64 diedAt = _deceasedAt[willId];
        if (diedAt != 0) revert TestatorDeceased(diedAt);
        if (docHash == bytes32(0)) revert EmptyHash();

        Version[] storage versions = _versions[willId];
        uint256 count = versions.length;
        if (count > 0 && versions[count - 1].docHash == docHash) revert DuplicateVersion();

        versions.push(Version({docHash: docHash, filedAt: uint64(block.timestamp), notary: msg.sender}));
        emit WillFiled(willId, count, docHash, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Public views (no wallet needed)
    // ---------------------------------------------------------------------

    /// @notice Returns every version of a will, oldest first.
    /// @param willId The will identifier.
    /// @return The full version history (empty if nothing was filed).
    function getVersions(string calldata willId) external view returns (Version[] memory) {
        return _versions[willId];
    }

    /// @notice Returns the most recent version of a will.
    /// @dev Reverts with NoWillFiled if the will has no versions.
    /// @param willId The will identifier.
    /// @return The latest version.
    function getLatest(string calldata willId) external view returns (Version memory) {
        Version[] storage versions = _versions[willId];
        if (versions.length == 0) revert NoWillFiled();
        return versions[versions.length - 1];
    }

    /// @notice Returns how many versions a will has.
    /// @param willId The will identifier.
    /// @return The number of filed versions.
    function versionCount(string calldata willId) external view returns (uint256) {
        return _versions[willId].length;
    }

    /// @notice Returns when the testator's death was recorded.
    /// @param willId The will identifier.
    /// @return Block timestamp of the death record, or 0 if none.
    function deceasedAt(string calldata willId) external view returns (uint64) {
        return _deceasedAt[willId];
    }

    /// @notice Returns whether an address is an approved notary.
    /// @param account The address to check.
    /// @return True if the address can file wills.
    function isNotary(address account) external view returns (bool) {
        return _notaries[account];
    }

    /// @notice Checks whether a document hash matches any filed version of a will.
    /// @dev If the same hash appears more than once, the most recent match is returned.
    /// @param willId The will identifier.
    /// @param docHash SHA-256 hash of the document to verify.
    /// @return found True if the hash matches a filed version.
    /// @return index Position of the matching version (0 if not found).
    /// @return isLatest True if the match is the current version.
    function findVersion(string calldata willId, bytes32 docHash)
        external
        view
        returns (bool found, uint256 index, bool isLatest)
    {
        Version[] storage versions = _versions[willId];
        uint256 count = versions.length;
        for (uint256 i = count; i > 0; i--) {
            if (versions[i - 1].docHash == docHash) {
                return (true, i - 1, i == count);
            }
        }
        return (false, 0, false);
    }
}
