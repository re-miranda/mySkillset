"""MIR-891: apply proves both flagged renames before its first document write."""
from __future__ import annotations

import os

# instruction_fixtures puts the reviewed source directory on sys.path; import it first.
from instruction_fixtures import (
    FaultInstructionFiles, InstructionFixture, UnsupportedExchange,
    signature_without_directory_mtimes, tree_signature)
from exchange import exchange, move_without_replace
from transaction import apply_plan

ORIGINAL = b"original user rules\n"
OLD_MTIME_NS = 1_500_000_000_000_000_000
SWAP = "expected atomic rename-exchange support"
MOVE = "expected atomic no-replace rename support"
# Which capability the filesystem lacks, and what the refusal must therefore name.
MISSING: dict[str, tuple[str, ...]] = {"exchange": (SWAP,), "no-replace": (MOVE,),
                                       "both": (SWAP, MOVE)}


def files_without(missing: str) -> FaultInstructionFiles:
    """Build the boundary for one unsupporting filesystem; e.g. files_without("both")."""
    swap = exchange if missing == "no-replace" else UnsupportedExchange()
    move = move_without_replace if missing == "exchange" else UnsupportedExchange()
    return FaultInstructionFiles(swap, move)


class RenamePreflightTests(InstructionFixture):
    def assert_refused_without_trace(self, missing: str) -> str:
        """Share the MIR-891 assertions; e.g. the cause is named and the tree is as before."""
        plan, before = self.plan(), signature_without_directory_mtimes(self.root)
        with self.assertRaises(ValueError) as raised:
            apply_plan(plan, files_without(missing))
        for wanted in MISSING[missing]:
            self.assertIn(wanted, str(raised.exception))
        self.assertEqual(before, signature_without_directory_mtimes(self.root))
        for leftover in ("journal.json", ".tmux-agents-*", "backups"):
            self.assertEqual(list(self.root.rglob(leftover)), [])
        self.assertFalse(self.alias.is_symlink())
        return str(raised.exception)

    def test_fresh_install_is_refused_before_any_write(self) -> None:
        """Without either rename a first install leaves no document, alias or directory."""
        for missing in MISSING:
            with self.subTest(missing=missing):
                self.assert_refused_without_trace(missing)
                self.assertFalse(self.pi.exists() or self.claude.exists())

    def test_refused_run_does_not_rewind_the_surviving_parent_mtime(self) -> None:
        """MIR-892: the directory that briefly held the created ones keeps its new mtime."""
        os.utime(self.root, ns=(OLD_MTIME_NS, OLD_MTIME_NS))
        self.assert_refused_without_trace("both")
        self.assertGreater(self.root.stat().st_mtime_ns, OLD_MTIME_NS)

    def test_existing_document_is_refused_before_any_write(self) -> None:
        """Without either rename an existing document keeps its bytes, inode and mtime."""
        self.seed_canonical(ORIGINAL, 0o664)
        for missing in MISSING:
            with self.subTest(missing=missing):
                self.assert_refused_without_trace(missing)
                self.assertEqual(self.canonical.read_bytes(), ORIGINAL)

    def test_refusal_names_the_cause_and_not_a_journal(self) -> None:
        """The error carries platform, device and the kernel's answer, and no recovery path."""
        self.seed_canonical(ORIGINAL)
        message = self.assert_refused_without_trace("both")
        self.assertRegex(message, r"platform='\w+' filesystem device=\d+")
        self.assertIn("fixture: no exchange for", message)
        self.assertIn("before the first document write", message)
        self.assertNotIn("journal", message)
        self.assertNotIn("partial instruction publication", message)

    def test_already_current_pair_needs_no_probe_and_stays_write_free(self) -> None:
        """The no-op path returns before the probe, even where neither rename works."""
        self.seed_canonical()
        self.seed_alias()
        apply_plan(self.plan(), self.files)
        plan, before = self.plan(), tree_signature(self.root)
        self.assertIsNone(apply_plan(plan, files_without("both")))
        self.assertEqual(before, tree_signature(self.root))


class RefusalSignatureTests(InstructionFixture):
    def test_only_a_directory_mtime_is_excused(self) -> None:
        """A touched directory compares equal; a leftover entry or a touched file does not."""
        self.seed_canonical(ORIGINAL)
        before, strict = signature_without_directory_mtimes(self.root), tree_signature(self.root)
        os.utime(self.pi, ns=(OLD_MTIME_NS, OLD_MTIME_NS))
        self.assertEqual(before, signature_without_directory_mtimes(self.root))
        self.assertNotEqual(strict, tree_signature(self.root))
        os.utime(self.canonical, ns=(OLD_MTIME_NS, OLD_MTIME_NS))
        self.assertNotEqual(before, signature_without_directory_mtimes(self.root))

    def test_a_leftover_or_changed_entry_is_still_a_trace(self) -> None:
        """A new directory, a mode change and a new link each break equality."""
        self.seed_canonical(ORIGINAL)
        before = signature_without_directory_mtimes(self.root)
        (self.pi / "backups").mkdir()
        self.assertNotEqual(before, signature_without_directory_mtimes(self.root))
        (self.pi / "backups").rmdir()
        self.assertEqual(before, signature_without_directory_mtimes(self.root))
        self.pi.chmod(0o750)
        self.assertNotEqual(before, signature_without_directory_mtimes(self.root))
