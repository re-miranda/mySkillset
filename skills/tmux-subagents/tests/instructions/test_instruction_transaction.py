"""Atomic publication, conditional rollback and recoverable partial failures."""
from __future__ import annotations

import errno
import os
from dataclasses import replace
from pathlib import Path

from instruction_fixtures import CollidingStageFiles, InstructionFixture, tree_signature
from refusals import swap_refusal_outcome
from records import Image, Plan
from transaction import (
    apply_plan, read_document, remove_created_directory, rollback_journal, rollback_record,
    verify_recovery_parent, write_document)


class InstructionTransactionTests(InstructionFixture):
    def test_fresh_pair_no_legacy_output_and_repeat_noop(self) -> None:
        """A fresh pair emits no legacy output and a repeat run is a no-op."""
        journal = apply_plan(self.plan(), self.files)
        self.assertIsNotNone(journal)
        self.assertEqual(self.canonical.read_bytes(), self.template)
        self.assertEqual(self.canonical.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.alias.resolve(), self.canonical)
        self.assertFalse(list(self.root.rglob("CLAUDE.md")))
        for path in (self.pi, self.alias.parent, journal.parent):
            self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        before = tree_signature(self.root)
        self.assertIsNone(apply_plan(self.plan(), self.files))
        self.assertEqual(before, tree_signature(self.root))

    def test_update_retains_unowned_content_mode_owner_group_and_alias(self) -> None:
        """An update keeps unowned content, mode, owner, group and alias."""
        self.seed_canonical(b"user\xff\r\n\r\n", 0o664)
        self.seed_alias()
        before, alias_before = self.files.snapshot(self.canonical), self.files.snapshot(self.alias)
        journal = apply_plan(self.plan(), self.files)
        after = self.files.snapshot(self.canonical)
        self.assertTrue(after.payload.startswith(before.payload))
        self.assertEqual((after.mode, after.uid, after.gid), (before.mode, before.uid, before.gid))
        self.assertEqual(alias_before, self.files.snapshot(self.alias))
        self.assertTrue(journal.is_relative_to(self.pi / "backups"))
        for path in journal.parent.rglob("*"):
            self.assertEqual(path.stat().st_mode & 0o777, 0o700 if path.is_dir() else 0o600)

    def test_holding_based_rollback_restores_content_mode_and_mtime(self) -> None:
        """Rollback from the holding copy restores content, mode and mtime."""
        self.seed_canonical(b"user original\r\n", 0o664)
        self.seed_alias()
        before = self.files.snapshot(self.canonical)
        journal = apply_plan(self.plan(), self.files)
        rollback_journal(journal, self.files)
        after = self.files.snapshot(self.canonical)
        self.assertEqual((after.payload, after.mode, after.mtime_ns),
                         (before.payload, before.mode, before.mtime_ns))
        before_repeat = tree_signature(self.root)
        rollback_journal(journal, self.files)
        # Journal phase is current too: repeated rollback must not rewrite it.
        self.assertEqual(before_repeat, tree_signature(self.root))

    def test_payload_fallback_when_holding_is_unavailable(self) -> None:
        """Rollback falls back to the stored payload when holding is unavailable."""
        self.seed_canonical(b"payload fallback user rules\n", 0o664)
        before = self.files.snapshot(self.canonical)
        journal = apply_plan(self.plan(), self.files)
        (journal.parent / "holding" / "canonical").unlink()
        rollback_journal(journal, self.files)
        restored = self.files.snapshot(self.canonical)
        self.assertEqual((restored.payload, restored.mode, restored.mtime_ns),
                         (before.payload, before.mode, before.mtime_ns))
        self.assertFalse(self.alias.parent.exists())

    def test_new_pair_rollback_removes_only_created_native_entries(self) -> None:
        """Rolling back a new pair removes only entries it created."""
        journal = apply_plan(self.plan(), self.files)
        rollback_journal(journal, self.files)
        self.assertFalse(self.canonical.exists())
        self.assertFalse(self.alias.is_symlink())
        self.assertFalse(self.alias.parent.exists())
        self.assertTrue(journal.exists())

    def test_existing_alias_link_metadata_recovers_without_holding(self) -> None:
        """An existing alias link recovers its metadata without holding."""
        self.seed_canonical(self.template)
        self.seed_alias()
        plan = self.plan()
        # Explicit fixture journal models a separately-approved recorded withdrawal.
        self.alias.unlink()
        journal = self.root / "fixture-journal.json"
        record: dict[str, object] = {"plan": plan.encode(), "canonical_after": plan.before.encode(),
                                    "alias_after": Image("absent").encode()}
        rollback_record(journal, record, self.files)
        after = self.files.snapshot(self.alias)
        self.assertEqual((after.link, after.uid, after.gid, after.mtime_ns),
                         (plan.alias_before.link, plan.alias_before.uid,
                          plan.alias_before.gid, plan.alias_before.mtime_ns))

    def test_link_recovery_refuses_unpreservable_group_before_writes(self) -> None:
        """Link recovery refuses an unpreservable group before any write."""
        self.seed_canonical(self.template)
        self.seed_alias()
        plan = self.plan()
        foreign_group = max(self.files.groups) + 1
        plan = replace(plan, alias_before=replace(plan.alias_before, gid=foreign_group))
        self.alias.unlink()
        record: dict[str, object] = {"plan": plan.encode(), "canonical_after": plan.before.encode(),
                                    "alias_after": Image("absent").encode()}
        before = tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "expected preservable execution owner/group"):
            rollback_record(self.root / "fixture-journal.json", record, self.files)
        self.assertEqual(before, tree_signature(self.root))

    def test_scratch_collision_does_not_delete_someone_elses_file(self) -> None:
        """A scratch-name collision never deletes another party's file."""
        self.seed_canonical(b"original rules\n")
        before = self.files.snapshot(self.canonical)
        collision_files = CollidingStageFiles()
        with self.assertRaises(FileExistsError):
            collision_files.publish(self.canonical, before, self.template, before.mode, before.gid)
        self.assertEqual(before, self.files.snapshot(self.canonical))
        collisions = list(self.pi.glob(".tmux-agents-*"))
        self.assertEqual(len(collisions), 1)
        self.assertEqual(collisions[0].read_bytes(), b"concurrent temporary content")

    def test_before_publication_failure_preserves_original(self) -> None:
        """A failure before publication leaves the original intact."""
        self.seed_canonical(b"original user rules\n")
        before = self.files.snapshot(self.canonical)
        self.files.fail_publication = self.canonical
        with self.assertRaisesRegex(ValueError, "recovered; journal="):
            apply_plan(self.plan(), self.files)
        self.assertEqual(before, self.files.snapshot(self.canonical))

    def test_second_file_failure_conditionally_recovers_first(self) -> None:
        """A second-file failure recovers the first file only when safe."""
        self.seed_canonical(b"user rules before alias failure\n", 0o664)
        before = self.files.snapshot(self.canonical)
        self.files.fail_alias = True
        with self.assertRaisesRegex(ValueError, "recovered; journal="):
            apply_plan(self.plan(), self.files)
        restored = self.files.snapshot(self.canonical)
        self.assertEqual((restored.payload, restored.mode, restored.mtime_ns),
                         (before.payload, before.mode, before.mtime_ns))
        self.assertFalse(self.alias.parent.exists())

    def test_preflight_content_mode_alias_and_parent_drift_refuse_before_writes(self) -> None:
        """Drift in content, mode, alias or parents refuses before any write."""
        self.seed_canonical()
        self.seed_alias()
        for kind in ("content", "mode", "alias", "parent"):
            plan = self.plan()
            self._drift(kind)
            before = tree_signature(self.root)
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, "expected"):
                apply_plan(plan, self.files)
            self.assertEqual(before, tree_signature(self.root))
            if kind == "alias":
                self.alias.unlink()
                self.seed_alias()

    def _drift(self, kind: str) -> None:
        if kind == "content":
            self.canonical.write_bytes(b"different user rules\n")
        elif kind == "mode":
            self.canonical.chmod(0o600)
        elif kind == "alias":
            self.alias.unlink()
            self.alias.symlink_to("wrong.md")
        else:
            os.chmod(self.pi, 0o755)

    def test_immediate_publication_guard_preserves_concurrent_edit(self) -> None:
        """The pre-publication guard preserves a concurrent edit."""
        self.seed_canonical(b"old rules\n")
        self.files.drift_publication = self.canonical
        with self.assertRaisesRegex(ValueError, "partial instruction publication"):
            apply_plan(self.plan(), self.files)
        self.assertEqual(self.canonical.read_bytes(), b"concurrent user rules\n")
        journals = list(self.pi.rglob("journal.json"))
        self.assertEqual((journals[0].parent / "payload/canonical").read_bytes(), b"old rules\n")

    def test_unattested_after_state_reports_partial_not_false_rollback(self) -> None:
        """An unattested after-state reports partial, not a false rollback."""
        self.seed_canonical(b"original stays recoverable\n")
        self.files.post_publication_failure = self.canonical
        with self.assertRaisesRegex(ValueError, "partial instruction publication.*preserve journal="):
            apply_plan(self.plan(), self.files)
        self.assertTrue(self.canonical.read_bytes().startswith(b"original stays recoverable\n"))
        journal = next(self.pi.rglob("journal.json"))
        self.assertEqual((journal.parent / "payload/canonical").read_bytes(), b"original stays recoverable\n")

    def test_rollback_refuses_concurrent_edit_without_restoring_other_file(self) -> None:
        """Rollback refuses a concurrent edit and leaves the other file alone."""
        self.seed_canonical()
        journal = apply_plan(self.plan(), self.files)
        self.canonical.write_bytes(b"later user rules\n")
        before = tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "expected recorded after-state"):
            rollback_journal(journal, self.files)
        self.assertEqual(before, tree_signature(self.root))

    def test_missing_or_corrupt_recovery_bytes_never_replace_original_rules(self) -> None:
        """Missing or corrupt recovery bytes never replace the original rules."""
        self.seed_canonical()
        journal = apply_plan(self.plan(), self.files)
        for name in ("holding", "payload"):
            (journal.parent / name / "canonical").write_bytes(b"corrupted fixture copy")
        before = tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "expected verified holding or payload"):
            rollback_journal(journal, self.files)
        self.assertEqual(before, tree_signature(self.root))

    def test_private_record_shape_and_schema_are_enforced(self) -> None:
        """Private record shape and schema are enforced."""
        self.seed_canonical()
        journal = apply_plan(self.plan(), self.files)
        record = read_document(journal, self.files)
        record["schema"] = 42
        write_document(journal, record, self.files)
        with self.assertRaisesRegex(ValueError, "expected instruction recovery schema 1"):
            rollback_journal(journal, self.files)
        journal.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "expected owned private regular JSON"):
            read_document(journal, self.files)

    def test_recovery_parent_may_be_absent_only_when_the_plan_created_it(self) -> None:
        """An absent parent passes if the plan created it and raises otherwise (MIR-888)."""
        self.pi.mkdir(mode=0o700)
        recorded = self.files.parent(self.pi)
        verify_recovery_parent(recorded, (), self.files)
        self.pi.rmdir()
        verify_recovery_parent(recorded, (self.pi,), self.files)
        with self.assertRaises(FileNotFoundError):
            verify_recovery_parent(recorded, (), self.files)

    def test_created_directory_removal_keeps_populated_and_tolerates_absent(self) -> None:
        """Only an empty recorded directory goes; other errors still surface (MIR-888)."""
        self.pi.mkdir(mode=0o700)
        recorded = self.files.parent(self.pi)
        (self.pi / "user file").write_bytes(b"added since install\n")
        remove_created_directory(self.pi, recorded, self.files)
        self.assertTrue((self.pi / "user file").exists())
        (self.pi / "user file").unlink()
        self.root.chmod(0o500)
        self.addCleanup(self.root.chmod, 0o700)
        with self.assertRaises(PermissionError) as denied:
            remove_created_directory(self.pi, recorded, self.files)
        self.assertEqual(denied.exception.errno, errno.EACCES)
        self.root.chmod(0o700)
        remove_created_directory(self.pi, recorded, self.files)
        self.assertFalse(self.pi.exists())
        remove_created_directory(self.pi, None, self.files)

    def test_swap_refusal_outcome_claims_nothing_published_only_when_returned(self) -> None:
        """The wording follows where the user's version actually is (MIR-888)."""
        conflict = self.canonical.with_name(".tmux-agents-conflict-0a")
        returned = swap_refusal_outcome(self.canonical, self.canonical)
        self.assertEqual(
            returned, f"concurrent version preserved at {str(self.canonical)!r}, nothing published")
        stranded = swap_refusal_outcome(self.canonical, conflict)
        self.assertNotIn("nothing published", stranded)
        self.assertIn(f"canonical name {str(self.canonical)!r} holds the new payload", stranded)
        self.assertIn(f"preserved at {str(conflict)!r}", stranded)
