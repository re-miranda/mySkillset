"""MIR-891: apply proves both flagged renames before its first document write."""
from __future__ import annotations

# instruction_fixtures puts the reviewed source directory on sys.path; import it first.
from instruction_fixtures import (
    FaultInstructionFiles, InstructionFixture, UnsupportedExchange, tree_signature)
from exchange import exchange, move_without_replace
from transaction import apply_plan

ORIGINAL = b"original user rules\n"
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
        plan, before = self.plan(), tree_signature(self.root)
        with self.assertRaises(ValueError) as raised:
            apply_plan(plan, files_without(missing))
        for wanted in MISSING[missing]:
            self.assertIn(wanted, str(raised.exception))
        self.assertEqual(before, tree_signature(self.root))
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
