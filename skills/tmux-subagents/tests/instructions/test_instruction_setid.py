"""Setuid/setgid mode bits survive publication and rollback, or nothing is published (MIR-696 P2)."""
from __future__ import annotations

from instruction_fixtures import InstructionFixture, SuidClearingFiles, tree_signature
from transaction import apply_plan, rollback_journal

SETID_MODE = 0o6750
ORIGINAL = b"setid user rules\n"


class InstructionSetidTests(InstructionFixture):
    def test_setid_mode_survives_publish_rollback_and_repeat_rollback(self) -> None:
        """Reviewer's P2 reproduction: 06750 is installed, restored, and a second rollback is a no-op."""
        self.seed_canonical(ORIGINAL, SETID_MODE)
        self.assertEqual(self.files.snapshot(self.canonical).mode, SETID_MODE)
        journal = apply_plan(self.plan(), self.files)
        installed = self.files.snapshot(self.canonical)
        self.assertEqual(installed.mode, SETID_MODE)
        self.assertNotEqual(installed.payload, ORIGINAL)
        rollback_journal(journal, self.files)
        restored = self.files.snapshot(self.canonical)
        self.assertEqual((restored.mode, restored.payload), (SETID_MODE, ORIGINAL))
        before_repeat = tree_signature(self.root)
        rollback_journal(journal, self.files)
        self.assertEqual(before_repeat, tree_signature(self.root))

    def test_cleared_setid_bits_refuse_publication_and_keep_canonical(self) -> None:
        """A kernel that drops the bits after fchmod fails closed, naming both modes."""
        self.seed_canonical(ORIGINAL, SETID_MODE)
        before = self.files.snapshot(self.canonical)
        with self.assertRaisesRegex(ValueError, r"mode=0o750 .*expected 0o6750"):
            SuidClearingFiles().publish(self.canonical, before, self.template, before.mode,
                                        before.gid)
        self.assertEqual(before, self.files.snapshot(self.canonical))
        self.assertEqual(list(self.pi.glob(".tmux-agents-*")), [])

    def test_cleared_setid_bits_during_apply_recover_original(self) -> None:
        """Through the real apply path the refusal reports both modes and leaves the document as it was."""
        self.seed_canonical(ORIGINAL, SETID_MODE)
        before = self.files.snapshot(self.canonical)
        plan = self.plan()
        with self.assertRaisesRegex(ValueError, r"mode=0o750 .*expected 0o6750.*recovered; journal="):
            apply_plan(plan, SuidClearingFiles())
        self.assertEqual(before, self.files.snapshot(self.canonical))
