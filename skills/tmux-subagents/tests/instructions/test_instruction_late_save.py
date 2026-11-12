"""MIR-889: remove and publish never destroy or misattribute a late user save."""
from __future__ import annotations

import errno
import json
import os
from pathlib import Path

# instruction_fixtures puts the reviewed source directory on sys.path; import it first.
from instruction_fixtures import (
    EDITOR_SAVE, LATE_EDIT, RECREATED, USER_LINK, FaultInstructionFiles, InstructionFixture,
    LateSave, ReplaceAfterAliasFiles, SaveAfterPublishFiles, SaveAfterRestoreFiles,
    SaveBeforeRemoveFiles, UnsupportedExchange, replace_with_user_link, save_by_rename_over,
    save_in_place)
from files import removal_refusal_outcome, unsupported_rename
from records import Image
from transaction import apply_plan, rollback_journal

ORIGINAL = b"original user rules\n"
OLD_MTIME_NS = 1_500_000_000_000_000_000


class LateSaveFixture(InstructionFixture):
    def journal_record(self) -> dict[str, object]:
        """Read the single recovery journal; e.g. its phase and recorded after-images."""
        record: dict[str, object] = json.loads(next(self.pi.rglob("journal.json")).read_bytes())
        return record


class LateSaveRemovalTests(LateSaveFixture):
    def assert_rollback_keeps_canonical_save(self, journal: Path, save: LateSave,
                                             saved: bytes) -> None:
        """Share the MIR-889 P0 assertions; e.g. the save is canonical and rollback did not succeed."""
        late = SaveBeforeRemoveFiles(self.canonical, save)
        with self.assertRaisesRegex(ValueError, "returned to .*nothing removed"):
            rollback_journal(journal, late)
        self.assertTrue(late.late.saved)
        self.assertEqual(self.canonical.read_bytes(), saved)
        self.assertEqual(self.journal_record()["phase"], "complete")
        self.assertEqual(self.scratch_names(), [])

    def test_in_place_save_before_canonical_removal_survives_rollback(self) -> None:
        """Reviewer's P0 reproduction: rolling back a new document keeps a save made just before."""
        journal = apply_plan(self.plan(), self.files)
        self.assert_rollback_keeps_canonical_save(journal, save_in_place, LATE_EDIT)

    def test_rename_over_before_canonical_removal_survives_rollback(self) -> None:
        """An editor's rename-over just before the removal survives and rollback refuses."""
        journal = apply_plan(self.plan(), self.files)
        self.assert_rollback_keeps_canonical_save(journal, save_by_rename_over, EDITOR_SAVE)

    def test_alias_replaced_before_removal_survives_rollback(self) -> None:
        """A user's own link that replaced the alias is returned to the name, not removed."""
        journal = apply_plan(self.plan(), self.files)
        late = SaveBeforeRemoveFiles(self.alias, replace_with_user_link)
        with self.assertRaisesRegex(ValueError, "returned to .*nothing removed"):
            rollback_journal(journal, late)
        self.assertTrue(late.late.saved)
        self.assertEqual(self.alias.readlink().as_posix(), USER_LINK)
        self.assertEqual(self.canonical.read_bytes(), self.template)
        self.assertEqual(list(self.alias.parent.glob(".tmux-agents-*")), [])

    def test_failed_return_keeps_both_versions_and_names_both_paths(self) -> None:
        """If the name was re-created meanwhile, neither version is overwritten or unlinked."""
        self.seed_canonical(ORIGINAL)
        expected = self.files.snapshot(self.canonical)
        late = SaveBeforeRemoveFiles(self.canonical, save_in_place, recreate=True)
        with self.assertRaises(ValueError) as raised:
            late.remove(self.canonical, expected)
        names = self.scratch_names()
        self.assertEqual(len(names), 1)
        self.assertTrue(names[0].startswith(".tmux-agents-conflict-"))
        self.assertEqual(self.canonical.read_bytes(), RECREATED)
        self.assertEqual((self.pi / names[0]).read_bytes(), LATE_EDIT)
        self.assertIn(f"the name {str(self.canonical)!r} keeps", str(raised.exception))
        self.assertIn(f"preserved at {str(self.pi / names[0])!r}", str(raised.exception))

    def test_unsupported_no_replace_rename_refuses_and_leaves_entry_untouched(self) -> None:
        """Without the no-replace rename, remove fails closed instead of unlinking by name."""
        journal = apply_plan(self.plan(), self.files)
        before = self.canonical.lstat()
        unsupported = FaultInstructionFiles(move=UnsupportedExchange())
        with self.assertRaisesRegex(ValueError, "expected atomic no-replace rename support"):
            unsupported.remove(self.canonical, self.files.snapshot(self.canonical))
        with self.assertRaisesRegex(ValueError, "expected atomic no-replace rename support"):
            rollback_journal(journal, unsupported)
        after = self.canonical.lstat()
        self.assertEqual((after.st_ino, after.st_mtime_ns, after.st_ctime_ns),
                         (before.st_ino, before.st_mtime_ns, before.st_ctime_ns))
        self.assertEqual(self.canonical.read_bytes(), self.template)
        self.assertTrue(self.alias.is_symlink())

    def test_remove_of_absent_entry_refuses_without_creating_anything(self) -> None:
        """An entry that vanished is reported, and no scratch name is left behind."""
        self.pi.mkdir(mode=0o700)
        with self.assertRaisesRegex(ValueError, "is absent; expected the transaction after-state"):
            self.files.remove(self.canonical, Image("absent"))
        self.assertEqual(list(self.pi.iterdir()), [])

    def test_removal_refusal_outcome_names_every_path_holding_a_version(self) -> None:
        """The wording follows where the moved entry ended up."""
        conflict = self.canonical.with_name(".tmux-agents-conflict-0a")
        returned = removal_refusal_outcome(self.canonical, self.canonical)
        self.assertIn(f"returned to {str(self.canonical)!r}, nothing removed", returned)
        stranded = removal_refusal_outcome(self.canonical, conflict)
        self.assertIn(f"the name {str(self.canonical)!r} keeps", stranded)
        self.assertIn(f"preserved at {str(conflict)!r}", stranded)

    def test_unsupported_rename_names_path_platform_device_and_cause(self) -> None:
        """The fail-closed refusal carries the entry, the wanted call and the kernel's answer."""
        cause = OSError(errno.EINVAL, "fixture: flags rejected")
        refusal = unsupported_rename(Path("/p/AGENTS.md"), 42, "swap support", cause)
        self.assertIsInstance(refusal, ValueError)
        self.assertIn("entry='/p/AGENTS.md'", str(refusal))
        self.assertIn("device=42; expected atomic swap support, got", str(refusal))
        self.assertIn("fixture: flags rejected; entry left untouched", str(refusal))


class LateSavePublicationTests(LateSaveFixture):
    def assert_apply_does_not_record(self, save: LateSave, saved: bytes) -> None:
        """Share the MIR-889 P1 assertions; e.g. the save stays and is never canonical_after."""
        with self.assertRaisesRegex(ValueError, "expected our staged entry device="):
            apply_plan(self.plan(), SaveAfterPublishFiles(self.canonical, save))
        self.assertEqual(self.canonical.read_bytes(), saved)
        record = self.journal_record()
        self.assertEqual(record["phase"], "prepared")
        self.assertNotEqual(Image.decode(record["canonical_after"]).payload, saved)
        with self.assertRaisesRegex(ValueError, "expected recorded after-state"):
            rollback_journal(next(self.pi.rglob("journal.json")), self.files)
        self.assertEqual(self.canonical.read_bytes(), saved)
        self.assertEqual(self.scratch_names(), [])

    def test_in_place_save_after_swap_is_not_recorded_as_published(self) -> None:
        """Reviewer's P1 reproduction: a save right after the swap is not our output."""
        self.seed_canonical(ORIGINAL)
        self.assert_apply_does_not_record(save_in_place, LATE_EDIT)

    def test_rename_over_after_swap_is_not_recorded_as_published(self) -> None:
        """An editor's rename-over right after the swap is not our output either."""
        self.seed_canonical(ORIGINAL)
        self.assert_apply_does_not_record(save_by_rename_over, EDITOR_SAVE)

    def test_save_after_link_into_absent_name_is_not_recorded(self) -> None:
        """The absent (link) branch proves its output the same way as the swap branch."""
        self.assertFalse(self.canonical.exists())
        self.assert_apply_does_not_record(save_in_place, LATE_EDIT)

    def test_refusal_names_path_and_both_identities_without_content(self) -> None:
        """The error carries the path, the entry found and the staged identity expected."""
        self.seed_canonical(ORIGINAL)
        before = self.files.snapshot(self.canonical)
        late = SaveAfterPublishFiles(self.canonical, save_by_rename_over)
        with self.assertRaises(ValueError) as raised:
            late.publish(self.canonical, before, self.template, before.mode, before.gid)
        found = self.canonical.lstat()
        message = str(raised.exception)
        self.assertIn(f"entry={str(self.canonical)!r} kind=regular identity=({found.st_dev}, "
                      f"{found.st_ino},", message)
        self.assertRegex(message, rf"expected our staged entry device={found.st_dev} inode=\d+ "
                                  rf"bytes={len(self.template)} mtime_ns=\d+")
        self.assertNotIn(EDITOR_SAVE.decode().strip(), message)

    def test_save_in_restore_swap_window_blocks_rollback(self) -> None:
        """During rollback a save right after the restoring swap stays and rollback refuses."""
        self.seed_canonical(ORIGINAL)
        self.seed_alias()
        journal = apply_plan(self.plan(), self.files)
        with self.assertRaisesRegex(ValueError, "expected our staged entry device="):
            rollback_journal(journal, SaveAfterPublishFiles(self.canonical))
        self.assertEqual(self.canonical.read_bytes(), LATE_EDIT)
        self.assertEqual(self.journal_record()["phase"], "complete")

    def test_save_after_restore_keeps_its_own_mtime(self) -> None:
        """No by-name metadata call follows a restore, so a later save's mtime is untouched."""
        self.seed_canonical(ORIGINAL)
        self.seed_alias()
        # A fixed old mtime: the kernel clock is coarse, so "now" twice can be the same tick.
        os.utime(self.canonical, ns=(OLD_MTIME_NS, OLD_MTIME_NS))
        before = self.files.snapshot(self.canonical)
        journal = apply_plan(self.plan(), self.files)
        late = SaveAfterRestoreFiles(self.canonical)
        rollback_journal(journal, late)
        self.assertEqual(self.canonical.read_bytes(), LATE_EDIT)
        self.assertEqual(before.mtime_ns, OLD_MTIME_NS)
        self.assertGreater(late.saved_mtime_ns, OLD_MTIME_NS)
        self.assertEqual(self.canonical.lstat().st_mtime_ns, late.saved_mtime_ns)

    def test_alias_replaced_after_creation_is_not_recorded(self) -> None:
        """An entry that replaced the new link is left alone and never becomes alias_after."""
        with self.assertRaisesRegex(ValueError, "expected our staged entry device="):
            apply_plan(self.plan(), ReplaceAfterAliasFiles(self.alias))
        self.assertEqual(self.alias.readlink().as_posix(), USER_LINK)
        record = self.journal_record()
        self.assertNotEqual(record["phase"], "complete")
        self.assertEqual(Image.decode(record["alias_after"]).kind, "absent")
        with self.assertRaisesRegex(ValueError, "expected recorded after-state"):
            rollback_journal(next(self.pi.rglob("journal.json")), self.files)
        self.assertEqual(self.alias.readlink().as_posix(), USER_LINK)

    def test_created_alias_is_proven_by_inode_and_text(self) -> None:
        """The returned image is the link just created, and no scratch link is left."""
        self.alias.parent.mkdir(mode=0o700, parents=True)
        image = self.files.create_alias(self.alias, "../pi agent/AGENTS.md")
        found = self.alias.lstat()
        self.assertEqual((image.kind, image.link), ("link", "../pi agent/AGENTS.md"))
        self.assertEqual(image.identity[:3], (found.st_dev, found.st_ino, 1))
        self.assertEqual([path.name for path in self.alias.parent.iterdir()], ["AGENTS.md"])
