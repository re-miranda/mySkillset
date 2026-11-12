"""MIR-891: the rename probe itself, its cleanup, and the helpers it rests on."""
from __future__ import annotations

import errno
import os
from pathlib import Path
from unittest import mock

# instruction_fixtures puts the reviewed source directory on sys.path; import it first.
from instruction_fixtures import (
    FaultInstructionFiles, InstructionFixture, UnsupportedExchange, tree_signature)
from rename_fakes import BrokenRename, DeniedUtime, FlagIgnoringRename
from exchange import exchange, move_without_replace
from refusals import refuse_unsupported_rename
from rename_probe import ABSENT_INODE, probe_inode, prove_renames
from transaction import apply_plan, surviving_parent_mtimes, unproven_renames_refusal

OLD_MTIME_NS = 1_500_000_000_000_000_000


class RenameProbeTests(InstructionFixture):
    def private_directory(self) -> Path:
        """Stand in for the run's recovery directory; e.g. an empty 0700 fixture directory."""
        private = self.root / "private recovery"
        private.mkdir(mode=0o700)
        return private

    def test_probe_on_a_supporting_filesystem_leaves_nothing_behind(self) -> None:
        """Both renames pass on the fixture filesystem and every scratch entry is removed."""
        private = self.private_directory()
        prove_renames(self.files, private)
        self.assertEqual(list(private.iterdir()), [])

    def test_successful_apply_leaves_only_recovery_records(self) -> None:
        """After a real install the recovery directory holds no probe entry."""
        self.seed_canonical(b"original user rules\n")
        journal = apply_plan(self.plan(), self.files)
        assert journal is not None
        self.assertEqual(sorted(path.name for path in journal.parent.iterdir()),
                         ["holding", "journal.json", "payload"])
        self.assertEqual(list(self.root.rglob(".tmux-agents-*")), [])

    def test_probe_names_every_missing_capability(self) -> None:
        """With neither rename, one refusal lists both and the directory is empty again."""
        private = self.private_directory()
        unsupporting = FaultInstructionFiles(UnsupportedExchange(), UnsupportedExchange())
        with self.assertRaisesRegex(ValueError, "rename-exchange support.*; also .*no-replace"):
            prove_renames(unsupporting, private)
        self.assertEqual(list(private.iterdir()), [])

    def test_rename_that_ignores_its_flag_is_refused(self) -> None:
        """A call that reports success but renames plainly counts as unsupported."""
        private = self.private_directory()
        cases = ((FaultInstructionFiles(swap=FlagIgnoringRename()), "rename-exchange support"),
                 (FaultInstructionFiles(move=FlagIgnoringRename()), "no-replace rename support"))
        for ignoring, wanted in cases:
            with self.subTest(wanted=wanted), self.assertRaises(ValueError) as raised:
                prove_renames(ignoring, private)
            self.assertIn(f"expected atomic {wanted}", str(raised.exception))
            self.assertIn("rename flag was not honoured", str(raised.exception))
            self.assertEqual(list(private.iterdir()), [])

    def test_other_rename_failure_is_not_called_unsupported_and_leaves_no_trace(self) -> None:
        """An EIO in the probe surfaces as itself, and apply still removes what it created."""
        private = self.private_directory()
        broken = FaultInstructionFiles(swap=BrokenRename())
        with self.assertRaises(OSError) as raised:
            prove_renames(broken, private)
        self.assertEqual(raised.exception.errno, errno.EIO)
        self.assertEqual(list(private.iterdir()), [])
        plan, before = self.plan(), tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "fixture: rename failed.*were not written"):
            apply_plan(plan, broken)
        self.assertEqual(before, tree_signature(self.root))

    def test_probe_inode_reports_an_absent_name(self) -> None:
        """A missing scratch name reads as the absent marker instead of raising."""
        descriptor = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
        self.addCleanup(os.close, descriptor)
        self.assertEqual(probe_inode(descriptor, "never-created"), ABSENT_INODE)
        self.assertEqual(probe_inode(descriptor, "."), self.root.stat().st_ino)


class RenameProofHelperTests(InstructionFixture):
    def test_refuse_unsupported_rename_raises_only_for_missing_support(self) -> None:
        """EINVAL becomes the fail-closed refusal; another errno is left to the caller."""
        entry = Path("/p/AGENTS.md")
        with self.assertRaisesRegex(ValueError, "device=7; expected atomic swap support"):
            refuse_unsupported_rename(OSError(errno.EINVAL, "flags rejected"), entry, 7,
                                      "swap support")
        refuse_unsupported_rename(OSError(errno.EIO, "bad disk"), entry, 7, "swap support")

    def test_directory_mtime_is_read_and_restored(self) -> None:
        """The recorded mtime goes back on the directory through its descriptor."""
        os.utime(self.root, ns=(OLD_MTIME_NS, OLD_MTIME_NS))
        recorded = self.files.directory_mtime(self.root)
        (self.root / "child").mkdir()
        (self.root / "child").rmdir()
        self.assertNotEqual(self.root.stat().st_mtime_ns, OLD_MTIME_NS)
        self.files.restore_directory_mtime(self.root, recorded)
        self.assertEqual((recorded, self.root.stat().st_mtime_ns), (OLD_MTIME_NS, OLD_MTIME_NS))

    def test_unowned_parent_mtime_is_left_alone_without_failing(self) -> None:
        """A parent we may not stamp (sticky /tmp) does not turn the refusal into a crash."""
        current = self.root.stat().st_mtime_ns
        with mock.patch("os.utime", DeniedUtime()):
            self.files.restore_directory_mtime(self.root, OLD_MTIME_NS)
        self.assertEqual(self.root.stat().st_mtime_ns, current)

    def test_surviving_parent_mtimes_cover_only_directories_that_exist(self) -> None:
        """Only the existing parent of the topmost created directory is recorded."""
        missing = (self.pi, self.pi / "backups")
        recorded = surviving_parent_mtimes(missing, self.files)
        self.assertEqual(recorded, {self.root: self.root.stat().st_mtime_ns})

    def test_unproven_renames_refusal_leads_with_the_cause(self) -> None:
        """The wording keeps the kernel's answer first and names both untouched documents."""
        self.seed_canonical()
        message = unproven_renames_refusal(self.plan(), ValueError("expected atomic swap"))
        self.assertTrue(message.startswith("expected atomic swap; checked on scratch entries"))
        self.assertIn(repr((str(self.canonical), str(self.alias))), message)

    def test_real_renames_are_what_the_default_fixture_injects(self) -> None:
        """Guard the control: the passing probe above ran the kernel calls, not a fake."""
        self.assertIs(self.files.exchange, exchange)
        self.assertIs(self.files.move, move_without_replace)
