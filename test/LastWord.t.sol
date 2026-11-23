// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LastWord} from "../contracts/LastWord.sol";

contract LastWordTest is Test {
    LastWord registry;

    address admin = makeAddr("admin");
    address notaryA = makeAddr("notaryA");
    address notaryB = makeAddr("notaryB");
    address stranger = makeAddr("stranger");

    string constant WILL = "T-001";
    bytes32 immutable V1 = sha256("fake will T-001 v1");
    bytes32 immutable V2 = sha256("fake will T-001 v2");
    bytes32 immutable V3 = sha256("fake will T-001 v3");
    bytes32 immutable CERT = sha256("fake death certificate T-001");

    event NotaryAdded(address indexed notary);
    event NotaryRemoved(address indexed notary);
    event WillFiled(string willId, uint256 version, bytes32 docHash, address indexed notary);
    event DeathRecorded(string willId, bytes32 certHash);

    function setUp() public {
        vm.warp(1_700_000_000);
        vm.prank(admin);
        registry = new LastWord();

        vm.startPrank(admin);
        registry.addNotary(notaryA);
        registry.addNotary(notaryB);
        vm.stopPrank();
    }

    function _file(address notary, string memory willId, bytes32 docHash) internal {
        vm.prank(notary);
        registry.fileWill(willId, docHash);
    }

    // ------------------------------------------------------------------
    // Happy path
    // ------------------------------------------------------------------

    function test_AdminIsDeployer() public view {
        assertEq(registry.admin(), admin);
    }

    function test_FullLifecycle() public {
        // v0 filed
        _file(notaryA, WILL, V1);
        uint64 t0 = uint64(block.timestamp);

        // amendment by a different notary, a day later
        vm.warp(block.timestamp + 1 days);
        _file(notaryB, WILL, V2);
        uint64 t1 = uint64(block.timestamp);

        assertEq(registry.versionCount(WILL), 2);

        LastWord.Version[] memory vs = registry.getVersions(WILL);
        assertEq(vs.length, 2);
        assertEq(vs[0].docHash, V1);
        assertEq(vs[0].filedAt, t0);
        assertEq(vs[0].notary, notaryA);
        assertEq(vs[1].docHash, V2);
        assertEq(vs[1].filedAt, t1);
        assertEq(vs[1].notary, notaryB);

        LastWord.Version memory latest = registry.getLatest(WILL);
        assertEq(latest.docHash, V2);
        assertEq(latest.notary, notaryB);

        // death recorded
        vm.warp(block.timestamp + 30 days);
        vm.prank(admin);
        registry.recordDeath(WILL, CERT);
        assertEq(registry.deceasedAt(WILL), uint64(block.timestamp));

        // history is still readable and unchanged
        assertEq(registry.versionCount(WILL), 2);
        assertEq(registry.getLatest(WILL).docHash, V2);
    }

    function test_FileWill_EmitsEvent() public {
        vm.expectEmit(true, true, true, true, address(registry));
        emit WillFiled(WILL, 0, V1, notaryA);
        _file(notaryA, WILL, V1);

        vm.expectEmit(true, true, true, true, address(registry));
        emit WillFiled(WILL, 1, V2, notaryB);
        _file(notaryB, WILL, V2);
    }

    function test_AddRemoveNotary_EmitEventsAndUpdateRole() public {
        vm.expectEmit(true, true, true, true, address(registry));
        emit NotaryAdded(stranger);
        vm.prank(admin);
        registry.addNotary(stranger);
        assertTrue(registry.isNotary(stranger));

        vm.expectEmit(true, true, true, true, address(registry));
        emit NotaryRemoved(stranger);
        vm.prank(admin);
        registry.removeNotary(stranger);
        assertFalse(registry.isNotary(stranger));
    }

    function test_RecordDeath_EmitsEvent() public {
        _file(notaryA, WILL, V1);
        vm.expectEmit(true, true, true, true, address(registry));
        emit DeathRecorded(WILL, CERT);
        vm.prank(admin);
        registry.recordDeath(WILL, CERT);
    }

    function test_RefilingAnOlderVersionIsAllowed() public {
        // A will can be amended back to an earlier text; only an exact repeat of the latest is refused.
        _file(notaryA, WILL, V1);
        _file(notaryA, WILL, V2);
        _file(notaryA, WILL, V1);
        assertEq(registry.versionCount(WILL), 3);
        assertEq(registry.getLatest(WILL).docHash, V1);
    }

    function test_WillsAreIndependent() public {
        _file(notaryA, "T-001", V1);
        _file(notaryA, "T-002", V1); // same hash on a different will is fine
        vm.prank(admin);
        registry.recordDeath("T-001", CERT);

        // T-002 is unaffected by T-001's death record
        _file(notaryA, "T-002", V2);
        assertEq(registry.versionCount("T-002"), 2);
        assertEq(registry.deceasedAt("T-002"), 0);
    }

    function test_RemovedNotaryHistoryStays() public {
        _file(notaryA, WILL, V1);
        vm.prank(admin);
        registry.removeNotary(notaryA);
        assertEq(registry.getLatest(WILL).notary, notaryA);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function test_Views_UnknownWill() public view {
        assertEq(registry.versionCount("T-999"), 0);
        assertEq(registry.getVersions("T-999").length, 0);
        assertEq(registry.deceasedAt("T-999"), 0);
        (bool found, uint256 index, bool isLatest) = registry.findVersion("T-999", V1);
        assertFalse(found);
        assertEq(index, 0);
        assertFalse(isLatest);
    }

    function test_IsNotary() public view {
        assertTrue(registry.isNotary(notaryA));
        assertFalse(registry.isNotary(stranger));
        assertFalse(registry.isNotary(admin));
    }

    function test_FindVersion() public {
        _file(notaryA, WILL, V1);
        _file(notaryA, WILL, V2);
        _file(notaryA, WILL, V3);

        (bool found, uint256 index, bool isLatest) = registry.findVersion(WILL, V1);
        assertTrue(found);
        assertEq(index, 0);
        assertFalse(isLatest);

        (found, index, isLatest) = registry.findVersion(WILL, V2);
        assertTrue(found);
        assertEq(index, 1);
        assertFalse(isLatest);

        (found, index, isLatest) = registry.findVersion(WILL, V3);
        assertTrue(found);
        assertEq(index, 2);
        assertTrue(isLatest);

        (found, index, isLatest) = registry.findVersion(WILL, sha256("forged will"));
        assertFalse(found);
        assertEq(index, 0);
        assertFalse(isLatest);
    }

    function test_FindVersion_RepeatedHashReturnsMostRecent() public {
        _file(notaryA, WILL, V1);
        _file(notaryA, WILL, V2);
        _file(notaryA, WILL, V1);
        (bool found, uint256 index, bool isLatest) = registry.findVersion(WILL, V1);
        assertTrue(found);
        assertEq(index, 2);
        assertTrue(isLatest);
    }

    // ------------------------------------------------------------------
    // Reverts: admin functions
    // ------------------------------------------------------------------

    function test_RevertWhen_NonAdminAddsNotary() public {
        vm.expectRevert(LastWord.NotAdmin.selector);
        vm.prank(stranger);
        registry.addNotary(stranger);
    }

    function test_RevertWhen_NotaryAddsNotary() public {
        vm.expectRevert(LastWord.NotAdmin.selector);
        vm.prank(notaryA);
        registry.addNotary(stranger);
    }

    function test_RevertWhen_NonAdminRemovesNotary() public {
        vm.expectRevert(LastWord.NotAdmin.selector);
        vm.prank(stranger);
        registry.removeNotary(notaryA);
    }

    function test_RevertWhen_NonAdminRecordsDeath() public {
        _file(notaryA, WILL, V1);
        vm.expectRevert(LastWord.NotAdmin.selector);
        vm.prank(notaryA);
        registry.recordDeath(WILL, CERT);
    }

    function test_RevertWhen_RecordDeathWithoutWill() public {
        vm.expectRevert(LastWord.NoWillFiled.selector);
        vm.prank(admin);
        registry.recordDeath("T-404", CERT);
    }

    function test_RevertWhen_RecordDeathTwice() public {
        _file(notaryA, WILL, V1);
        vm.startPrank(admin);
        registry.recordDeath(WILL, CERT);
        vm.expectRevert(LastWord.AlreadyDeceased.selector);
        registry.recordDeath(WILL, CERT);
        vm.stopPrank();
    }

    function test_RevertWhen_RecordDeathWithEmptyCertHash() public {
        _file(notaryA, WILL, V1);
        vm.expectRevert(LastWord.EmptyHash.selector);
        vm.prank(admin);
        registry.recordDeath(WILL, bytes32(0));
    }

    // ------------------------------------------------------------------
    // Reverts: fileWill
    // ------------------------------------------------------------------

    function test_RevertWhen_NonNotaryFiles() public {
        vm.expectRevert(LastWord.NotANotary.selector);
        vm.prank(stranger);
        registry.fileWill(WILL, V1);
    }

    function test_RevertWhen_AdminFilesWithoutBeingNotary() public {
        vm.expectRevert(LastWord.NotANotary.selector);
        vm.prank(admin);
        registry.fileWill(WILL, V1);
    }

    function test_RevertWhen_RemovedNotaryFiles() public {
        vm.prank(admin);
        registry.removeNotary(notaryA);
        vm.expectRevert(LastWord.NotANotary.selector);
        vm.prank(notaryA);
        registry.fileWill(WILL, V1);
    }

    function test_RevertWhen_NotaryFilesAfterDeath() public {
        _file(notaryA, WILL, V1);
        vm.prank(admin);
        registry.recordDeath(WILL, CERT);
        uint64 diedAt = uint64(block.timestamp);

        // Even much later, and from a different notary, the forged/backdated filing is refused.
        vm.warp(block.timestamp + 365 days);
        vm.expectRevert(abi.encodeWithSelector(LastWord.TestatorDeceased.selector, diedAt));
        vm.prank(notaryB);
        registry.fileWill(WILL, V2);

        assertEq(registry.versionCount(WILL), 1);
    }

    function test_RevertWhen_EmptyHash() public {
        vm.expectRevert(LastWord.EmptyHash.selector);
        vm.prank(notaryA);
        registry.fileWill(WILL, bytes32(0));
    }

    function test_RevertWhen_DuplicateOfLatest() public {
        _file(notaryA, WILL, V1);
        vm.expectRevert(LastWord.DuplicateVersion.selector);
        vm.prank(notaryB);
        registry.fileWill(WILL, V1);
    }

    function test_RevertWhen_GetLatestOnEmptyWill() public {
        vm.expectRevert(LastWord.NoWillFiled.selector);
        registry.getLatest("T-404");
    }

    // ------------------------------------------------------------------
    // Fuzz
    // ------------------------------------------------------------------

    function testFuzz_NonNotaryCannotFile(address caller, bytes32 docHash) public {
        vm.assume(!registry.isNotary(caller));
        vm.expectRevert(LastWord.NotANotary.selector);
        vm.prank(caller);
        registry.fileWill(WILL, docHash);
    }

    function testFuzz_FiledHashIsFindable(bytes32 docHash) public {
        vm.assume(docHash != bytes32(0));
        _file(notaryA, WILL, docHash);
        (bool found, uint256 index, bool isLatest) = registry.findVersion(WILL, docHash);
        assertTrue(found);
        assertEq(index, 0);
        assertTrue(isLatest);
    }
}
