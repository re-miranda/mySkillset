"""MIR-696 P0: publication swaps atomically and never destroys a concurrent version."""
from __future__ import annotations

import errno
import json
import os
from pathlib import Path
from unittest import mock

# instruction_fixtures puts the reviewed source directory on sys.path; import it first.
from instruction_fixtures import (
    EDITOR_SAVE, LATE_EDIT, SECOND_SAVE, FailingNextSync, FailingSwapBackExchange,
    FaultInstructionFiles, InstructionFixture, LateEditFiles, RenameOverFiles,
    RenameOverSwapBackExchange, SameTickSecondSaveExchange, SecondSaveExchange,
    UnsupportedExchange, UnsyncedSwapBackExchange, signature_without_directory_mtimes)
from exchange import exchange, move_without_replace
from transaction import apply_plan, rollback_journal

ORIGINAL = b"original user rules\n"


class InstructionExchangeTests(InstructionFixture):
    def assert_apply_refuses_keeping(self, saved: bytes) -> None:
        """Share the late-save assertions; e.g. the user's bytes, not ours, end up canonical."""
        with self.assertRaisesRegex(ValueError, "partial instruction publication.*displaced"):
            apply_plan(self.plan(), self.files)
        self.assertEqual(self.canonical.read_bytes(), saved)
        self.assertEqual(self.scratch_names(), [])
        journal = next(self.pi.rglob("journal.json"))
        self.assertEqual(json.loads(journal.read_bytes())["phase"], "prepared")
        for name in ("holding", "payload"):
            self.assertEqual((journal.parent / name / "canonical").read_bytes(), ORIGINAL)

    def test_late_in_place_edit_is_never_overwritten(self) -> None:
        """Reviewer's reproduction: a save after the final check survives and apply fails."""
        self.seed_canonical(ORIGINAL)
        self.files = LateEditFiles(self.canonical)
        self.assert_apply_refuses_keeping(LATE_EDIT)

    def test_late_editor_rename_over_is_never_overwritten(self) -> None:
        """An editor's atomic save after the final check survives and apply fails."""
        self.seed_canonical(ORIGINAL)
        self.files = RenameOverFiles(self.canonical)
        self.assert_apply_refuses_keeping(EDITOR_SAVE)

    def test_conflict_message_names_path_observed_and_expected_identity(self) -> None:
        """The refusal identifies the entry and both identities without echoing content."""
        self.seed_canonical(ORIGINAL)
        before = self.files.snapshot(self.canonical)
        late = LateEditFiles(self.canonical)
        with self.assertRaises(ValueError) as raised:
            late.publish(self.canonical, before, self.template, before.mode, before.gid)
        message = str(raised.exception)
        self.assertIn(f"entry={str(self.canonical)!r}", message)
        self.assertIn(f"bytes={len(LATE_EDIT)}", message)
        self.assertIn(f"expected kind=regular identity={before.identity}", message)
        self.assertNotIn(LATE_EDIT.decode().strip(), message)

    def test_unsupported_exchange_fails_closed_without_touching_canonical(self) -> None:
        """No swap support means no replacement, and apply refuses before writing anything."""
        self.seed_canonical(ORIGINAL, 0o664)
        self.files = FaultInstructionFiles(UnsupportedExchange())
        plan = self.plan()
        with self.assertRaisesRegex(ValueError, "expected atomic rename-exchange support"):
            self.files.publish(self.canonical, plan.before, self.template, 0o664, plan.before.gid)
        self.assertEqual(self.scratch_names(), [])
        # MIR-891: apply now finds out on scratch entries, so no journal or directory remains.
        before = signature_without_directory_mtimes(self.root)
        with self.assertRaisesRegex(ValueError, "expected atomic rename-exchange support.*"
                                                "before the first document write"):
            apply_plan(plan, self.files)
        self.assertEqual(before, signature_without_directory_mtimes(self.root))
        self.assertEqual(self.canonical.read_bytes(), ORIGINAL)
        self.assertEqual(list(self.root.rglob("journal.json")), [])

    def test_failed_swap_back_keeps_user_file_at_reported_conflict_path(self) -> None:
        """When the user's version cannot be returned, it survives under the reported name."""
        self.seed_canonical(ORIGINAL)
        before = self.files.snapshot(self.canonical)
        late = LateEditFiles(self.canonical, FailingSwapBackExchange())
        with self.assertRaises(ValueError) as raised:
            late.publish(self.canonical, before, self.template, before.mode, before.gid)
        names = self.scratch_names()
        self.assertEqual(len(names), 1)
        self.assertTrue(names[0].startswith(".tmux-agents-conflict-"))
        self.assertIn(repr(str(self.pi / names[0])), str(raised.exception))
        self.assertEqual((self.pi / names[0]).read_bytes(), LATE_EDIT)
        # MIR-888: the installer's payload is at the canonical name, so the error must say so.
        self.assertEqual(self.canonical.read_bytes(), self.template)
        self.assertIn(f"canonical name {str(self.canonical)!r} holds the new payload",
                      str(raised.exception))
        self.assertNotIn("nothing published", str(raised.exception))

    def test_rollback_refuses_late_edit_and_keeps_user_bytes(self) -> None:
        """The same late save during rollback blocks the restore instead of being lost."""
        self.seed_canonical(ORIGINAL)
        self.seed_alias()
        journal = apply_plan(self.plan(), self.files)
        with self.assertRaisesRegex(ValueError, "displaced.*nothing published"):
            rollback_journal(journal, LateEditFiles(self.canonical))
        self.assertEqual(self.canonical.read_bytes(), LATE_EDIT)
        self.assertEqual(self.scratch_names(), [])
        self.assertEqual(json.loads(journal.read_bytes())["phase"], "complete")

    def test_save_into_staged_file_before_swap_back_survives_cleanup(self) -> None:
        """Cleanup removes only our untouched scratch file, never one a user wrote into."""
        self.seed_canonical(ORIGINAL)
        before = self.files.snapshot(self.canonical)
        late = LateEditFiles(self.canonical, SecondSaveExchange())
        with self.assertRaises(ValueError) as raised:
            late.publish(self.canonical, before, self.template, before.mode, before.gid)
        self.assert_second_save_stranded_and_named(str(raised.exception))

    def assert_second_save_stranded_and_named(self, message: str) -> None:
        """Share the MIR-887 leftover assertions; e.g. the error carries the scratch path."""
        self.assertEqual(self.canonical.read_bytes(), LATE_EDIT)
        names = self.scratch_names()
        self.assertEqual(len(names), 1)
        self.assertEqual((self.pi / names[0]).read_bytes(), SECOND_SAVE)
        self.assertIn(repr(str(self.pi / names[0])), message)

    def test_rename_over_before_swap_back_survives_and_is_named(self) -> None:
        """A second save by rename-over ends up at the scratch name and the error says so."""
        self.seed_canonical(ORIGINAL)
        before = self.files.snapshot(self.canonical)
        late = LateEditFiles(self.canonical, RenameOverSwapBackExchange())
        with self.assertRaises(ValueError) as raised:
            late.publish(self.canonical, before, self.template, before.mode, before.gid)
        self.assert_second_save_stranded_and_named(str(raised.exception))

    def test_same_size_same_tick_save_into_staged_file_survives_cleanup(self) -> None:
        """Cleanup compares bytes, so a save that keeps our size and mtime is still kept."""
        self.seed_canonical(ORIGINAL)
        before = self.files.snapshot(self.canonical)
        late = LateEditFiles(self.canonical, SameTickSecondSaveExchange())
        with self.assertRaises(ValueError) as raised:
            late.publish(self.canonical, before, self.template, before.mode, before.gid)
        names = self.scratch_names()
        self.assertEqual(len(names), 1)
        self.assertEqual((self.pi / names[0]).read_bytes(), b"S" * len(self.template))
        self.assertIn(repr(str(self.pi / names[0])), str(raised.exception))
        self.assertEqual(self.canonical.read_bytes(), LATE_EDIT)

    def test_failed_sync_after_swap_back_reports_canonical_not_conflict(self) -> None:
        """A sync failure after a good swap back must not relabel our staged file as the user's."""
        self.seed_canonical(ORIGINAL)
        before = self.files.snapshot(self.canonical)
        sync = FailingNextSync()
        late = LateEditFiles(self.canonical, UnsyncedSwapBackExchange(sync))
        with mock.patch("os.fsync", sync), self.assertRaises(ValueError) as raised:
            late.publish(self.canonical, before, self.template, before.mode, before.gid)
        self.assertEqual(self.canonical.read_bytes(), LATE_EDIT)
        self.assertEqual(self.scratch_names(), [])
        self.assertIn(f"preserved at {str(self.canonical)!r}", str(raised.exception))
        self.assertNotIn(".tmux-agents-", str(raised.exception))
        self.assertIn("directory sync failed", str(raised.exception))

    def test_successful_swap_publishes_and_leaves_no_scratch(self) -> None:
        """The ordinary update goes through the swap and removes the displaced original."""
        self.seed_canonical(ORIGINAL, 0o664)
        inode = self.canonical.lstat().st_ino
        apply_plan(self.plan(), self.files)
        self.assertTrue(self.canonical.read_bytes().startswith(ORIGINAL))
        self.assertNotEqual(self.canonical.lstat().st_ino, inode)
        self.assertEqual(self.scratch_names(), [])


class KernelExchangeTests(InstructionFixture):
    def swap_fixture(self) -> tuple[int, Path, Path]:
        """Open a temporary directory with two files; e.g. (fd, left, right)."""
        left, right = self.root / "left", self.root / "right"
        left.write_bytes(b"left")
        right.write_bytes(b"right")
        descriptor = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
        self.addCleanup(os.close, descriptor)
        return descriptor, left, right

    def test_exchange_swaps_two_names_keeping_both_inodes(self) -> None:
        """The kernel swap moves both entries and destroys neither."""
        descriptor, left, right = self.swap_fixture()
        inodes = (left.lstat().st_ino, right.lstat().st_ino)
        exchange(descriptor, "left", "right")
        self.assertEqual((left.read_bytes(), right.read_bytes()), (b"right", b"left"))
        self.assertEqual((right.lstat().st_ino, left.lstat().st_ino), inodes)

    def test_exchange_failure_reports_errno_and_names(self) -> None:
        """A missing name raises its errno with both names and changes nothing."""
        descriptor, left, _ = self.swap_fixture()
        with self.assertRaisesRegex(OSError, r"names=\('left', 'absent'\)") as raised:
            exchange(descriptor, "left", "absent")
        self.assertEqual(raised.exception.errno, errno.ENOENT)
        self.assertEqual(left.read_bytes(), b"left")

    def test_unknown_platform_and_missing_symbol_are_unsupported(self) -> None:
        """Platforms without a known swap call fail with the errnos publication refuses on."""
        descriptor, left, right = self.swap_fixture()
        with self.assertRaisesRegex(OSError, "platform='plan9'") as unknown:
            exchange(descriptor, "left", "right", platform="plan9")
        self.assertEqual(unknown.exception.errno, errno.ENOTSUP)
        with self.assertRaisesRegex(OSError, "libc symbol='renameatx_np'") as missing:
            exchange(descriptor, "left", "right", platform="darwin")
        self.assertEqual(missing.exception.errno, errno.ENOSYS)
        self.assertEqual((left.read_bytes(), right.read_bytes()), (b"left", b"right"))

    def test_move_without_replace_moves_to_an_unused_name(self) -> None:
        """The no-replace rename moves the same inode to a free name."""
        descriptor, left, _ = self.swap_fixture()
        inode = left.lstat().st_ino
        move_without_replace(descriptor, "left", "aside")
        self.assertFalse(left.exists())
        self.assertEqual(((self.root / "aside").read_bytes(), (self.root / "aside").lstat().st_ino),
                         (b"left", inode))

    def test_move_without_replace_refuses_an_occupied_name(self) -> None:
        """An existing target raises EEXIST and both entries stay as they were."""
        descriptor, left, right = self.swap_fixture()
        with self.assertRaisesRegex(FileExistsError, r"names=\('left', 'right'\)"):
            move_without_replace(descriptor, "left", "right")
        self.assertEqual((left.read_bytes(), right.read_bytes()), (b"left", b"right"))

    def test_move_without_replace_is_unsupported_on_unknown_platforms(self) -> None:
        """A platform without a known no-replace rename fails with ENOTSUP and moves nothing."""
        descriptor, left, _ = self.swap_fixture()
        with self.assertRaisesRegex(OSError, "platform='plan9'") as unknown:
            move_without_replace(descriptor, "left", "aside", platform="plan9")
        self.assertEqual(unknown.exception.errno, errno.ENOTSUP)
        self.assertEqual(left.read_bytes(), b"left")
