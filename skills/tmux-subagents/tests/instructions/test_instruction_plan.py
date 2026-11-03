"""Admission regressions: inputs stay intact, including legacy discovery entries."""
from __future__ import annotations

import os
from pathlib import Path

from instruction_fixtures import (
    DeniedParentFiles, ForeignProfileParentFiles, InstructionFixture, tree_signature,
)
from files import InstructionFiles
from planning import BEGIN, END, OLD_BEGIN, OLD_END, owned_span, replacement, validate_template
from records import Image, Plan, integer, mapping, string


class InstructionPlanTests(InstructionFixture):
    def test_preflight_has_zero_target_writes(self) -> None:
        before = tree_signature(self.root)
        plan = self.plan()
        self.assertEqual(before, tree_signature(self.root))
        self.assertEqual(Plan.decode(plan.encode()), plan)

    def test_unowned_bytes_survive_current_and_previous_pairs(self) -> None:
        prefix = b"user\xff\r\n\r\n<!-- ai-memory:start -->\r\nprofile\r\n<!-- ai-memory:end -->\r\n"
        suffix = b"\r\n\r\nuser suffix without newline"
        for begin, end in ((BEGIN, END), (OLD_BEGIN, OLD_END)):
            with self.subTest(begin=begin):
                before = prefix + begin + b"\r\nold\r\n" + end + b"\r\n" + suffix
                self.assertEqual(replacement(before, self.template), prefix + self.template + suffix)

    def test_append_preserves_all_original_bytes(self) -> None:
        for before in (b"", b"user", b"user\n", b"user\r\n\r\n"):
            with self.subTest(before=before):
                self.assertTrue(replacement(before, self.template).startswith(before))
                self.assertEqual(replacement(before, self.template).count(BEGIN), 1)

    def test_malformed_duplicate_and_nested_pairs_refuse(self) -> None:
        cases = (BEGIN, END, BEGIN + b"\n" + OLD_END, BEGIN + b"\n" + BEGIN + b"\n" + END,
                 BEGIN + b"\n" + END + b"\n" + OLD_BEGIN + b"\n" + OLD_END)
        for payload in cases:
            with self.subTest(payload=payload), self.assertRaisesRegex(ValueError, "expected"):
                owned_span(payload)

    def test_template_requires_guard_inside_complete_current_pair(self) -> None:
        guardless = BEGIN + b"\nworkflow\n" + END + b"\n"
        for template in (guardless, b"outside\n" + self.template, self.template.rstrip(b"\n")):
            with self.subTest(template=template), self.assertRaisesRegex(ValueError, "expected"):
                validate_template(template)

    def test_canonical_symlink_hardlink_directory_and_fifo_refuse(self) -> None:
        self.pi.mkdir()
        other = self.root / "user.md"
        other.write_bytes(b"do not overwrite")
        for kind in ("symlink", "hardlink", "directory", "fifo"):
            self._seed_canonical_collision(kind, other)
            before = tree_signature(self.root)
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, "expected"):
                self.plan()
            self.assertEqual(before, tree_signature(self.root))
            self.canonical.rmdir() if kind == "directory" else self.canonical.unlink()

    def _seed_canonical_collision(self, kind: str, other: Path) -> None:
        if kind == "symlink":
            self.canonical.symlink_to(other)
        elif kind == "hardlink":
            os.link(other, self.canonical)
        elif kind == "directory":
            self.canonical.mkdir()
        else:
            os.mkfifo(self.canonical)

    def test_alias_collision_matrix_refuses_unchanged(self) -> None:
        self.seed_canonical()
        self.alias.parent.mkdir(parents=True)
        for kind in ("regular", "directory", "wrong", "dangling"):
            self._seed_alias_collision(kind)
            before = tree_signature(self.root)
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, "expected"):
                self.plan()
            self.assertEqual(before, tree_signature(self.root))
            self.alias.rmdir() if kind == "directory" else self.alias.unlink()

    def _seed_alias_collision(self, kind: str) -> None:
        if kind == "regular":
            self.alias.write_bytes(b"user alias collision")
        elif kind == "directory":
            self.alias.mkdir()
        else:
            self.alias.symlink_to(self.root / ("missing.md" if kind == "dangling" else "user.md"))

    def test_correct_link_to_missing_canonical_is_dangling_not_admitted(self) -> None:
        self.seed_alias()
        before = tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "expected exact native link"):
            self.plan()
        self.assertEqual(before, tree_signature(self.root))

    def test_parent_symlink_and_lexical_traversal_refuse(self) -> None:
        self.pi.symlink_to(self.root, target_is_directory=True)
        before = tree_signature(self.root)
        with self.assertRaises(OSError):
            self.plan()
        self.assertEqual(before, tree_signature(self.root))
        self.pi = self.root / "escape" / ".." / "different pi"
        with self.assertRaisesRegex(ValueError, "without parent traversal"):
            self.plan()

    def test_alias_lexical_escape_is_not_equivalent_to_native_link(self) -> None:
        self.seed_canonical()
        self.seed_alias("../../escape/../pi agent/AGENTS.md")
        before = tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "expected exact native link"):
            self.plan()
        self.assertEqual(before, tree_signature(self.root))

    def test_foreign_document_owner_is_rejected_by_io_boundary(self) -> None:
        self.seed_canonical()
        foreign_actor = InstructionFiles(os.getuid() + 1, {os.getgid()}, os.getgid())
        before = tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "owned single-link"):
            foreign_actor.snapshot(self.canonical)
        self.assertEqual(before, tree_signature(self.root))

    def test_recognized_legacy_blocks_require_native_proof_without_mutation(self) -> None:
        self.claude.mkdir()
        legacy = self.claude / "CLAUDE.md"
        for begin, end in ((BEGIN, END), (OLD_BEGIN, OLD_END)):
            legacy.write_bytes(begin + b"\nold released workflow\n" + end + b"\n")
            legacy.chmod(0o664)
            before = tree_signature(self.root)
            with self.subTest(begin=begin), self.assertRaisesRegex(ValueError, "native loading proof"):
                self.plan()
            self.assertEqual(before, tree_signature(self.root))

    def test_mixed_and_unknown_legacy_content_stops_without_guessing(self) -> None:
        self.claude.mkdir()
        legacy = self.claude / "CLAUDE.md"
        for payload in (b"user safety\n", b"custom\n" + BEGIN + b"\nold\n" + END + b"\n"):
            legacy.write_bytes(payload)
            before = tree_signature(self.root)
            with self.subTest(payload=payload), self.assertRaisesRegex(ValueError, "complete-content merge"):
                self.plan()
            self.assertEqual(before, tree_signature(self.root))

    def test_legacy_alias_is_detection_only_and_never_followed(self) -> None:
        self.seed_canonical()
        self.claude.mkdir()
        legacy = self.claude / "CLAUDE.md"
        legacy.symlink_to(self.canonical)
        before = tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "recognized legacy alias.*native loading proof"):
            self.plan()
        self.assertEqual(before, tree_signature(self.root))

    def test_foreign_profile_parent_refuses_without_chmod_or_substitution(self) -> None:
        self.seed_canonical()
        self.files = ForeignProfileParentFiles(self.pi)
        before = tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "expected execution-owner directory"):
            self.plan()
        self.assertEqual(before, tree_signature(self.root))

    def test_readonly_recovery_parent_refuses_before_native_creation(self) -> None:
        recovery = self.pi / "backups/tmux-subagents/instructions"
        recovery.mkdir(parents=True)
        self.files = DeniedParentFiles(recovery)
        before = tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "writable/executable destination or recovery"):
            self.plan()
        self.assertEqual(before, tree_signature(self.root))

    def test_completed_candidate_limit_refuses_before_writes(self) -> None:
        self.seed_canonical(b"u" * (1024 * 1024))
        before = tree_signature(self.root)
        with self.assertRaisesRegex(ValueError, "expected instruction document <=1MiB"):
            self.plan()
        self.assertEqual(before, tree_signature(self.root))

    def test_persisted_alias_and_parent_plan_drift_refuse(self) -> None:
        encoded = self.plan().encode()
        encoded["alias_text"] = "../wrong.md"
        with self.assertRaisesRegex(ValueError, "exact native alias text"):
            Plan.decode(encoded)
        encoded = self.plan().encode()
        encoded["missing"] = [str(self.root / "unrelated path")]
        with self.assertRaisesRegex(ValueError, "native destination/recovery ancestry"):
            Plan.decode(encoded)

    def test_typed_records_reject_bad_shapes(self) -> None:
        for operation, argument in ((mapping, []), (Image.decode, {"kind": "fifo"}),
                                    (Plan.decode, {"canonical": 42})):
            with self.subTest(operation=operation), self.assertRaises(ValueError):
                operation(argument)
        for operation in (integer, string):
            with self.subTest(operation=operation), self.assertRaisesRegex(ValueError, "expected"):
                operation({"field": True}, "field")
        self.assertEqual(Image.decode(Image("link", link="../AGENTS.md").encode()).link, "../AGENTS.md")
