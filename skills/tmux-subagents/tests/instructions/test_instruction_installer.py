"""Whole-installer regressions use whitelisted environments and isolated homes."""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from instruction_fixtures import InstructionFixture, SKILL_ROOT, tree_signature


class FixtureInstaller:
    """Run source only against named fixture roots, without native auth/provider environment."""

    def __init__(self, root: Path, pi: Path, claude: Path) -> None:
        """Bind every output; e.g. HOME and both configured native roots are temporary."""
        self.environment = {"HOME": str(root), "PATH": os.defpath, "LC_ALL": "C",
                            "CLAUDE_HOME": str(claude), "PI_AGENT_DIR": str(pi),
                            "PI_SUBAGENT_EXTENSION_DIR": str(root / "absent extension")}
        self.bash = shutil.which("bash")
        if self.bash is None:
            raise ValueError("bash=None; expected test prerequisite executable")

    def run(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        """Execute bounded fixture I/O; e.g. no inherited native HOME or model keys."""
        return subprocess.run([self.bash, str(SKILL_ROOT / "install.sh"), *arguments],
                              env=self.environment, capture_output=True, text=True, timeout=30,
                              check=False)


class PythonlessPath:
    """Expose bootstrap utilities, but genuinely no declared Python executable."""

    def __init__(self, directory: Path) -> None:
        """Seed a named runtime fake; e.g. prerequisite failure happens before mktemp/target writes."""
        directory.mkdir()
        self.directory = directory
        for command in ("dirname", "date"):
            executable = shutil.which(command)
            if executable is None:
                raise ValueError(f"{command}=None; expected test prerequisite utility")
            (directory / command).symlink_to(executable)


class InstructionInstallerTests(InstructionFixture):
    def installer(self) -> FixtureInstaller:
        """Select explicit homes; e.g. never reuse an installed profile for integration tests."""
        installer = FixtureInstaller(self.root, self.pi, self.claude)
        return installer

    def test_fresh_output_is_agents_only_and_reinstall_preserves_metadata(self) -> None:
        installer = self.installer()
        first = installer.run()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertTrue(self.canonical.is_file())
        self.assertEqual(self.alias.resolve(), self.canonical)
        self.assertFalse(list(self.root.rglob("CLAUDE.md")))
        before = tree_signature(self.root)
        second = installer.run()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(before, tree_signature(self.root))

    def test_dry_run_leaves_fresh_and_existing_roots_unchanged(self) -> None:
        installer = self.installer()
        before = tree_signature(self.root)
        result = installer.run("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, tree_signature(self.root))
        self.seed_canonical(b"unrelated user rules\r\n", 0o664)
        self.seed_alias()
        before = tree_signature(self.root)
        result = installer.run("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, tree_signature(self.root))

    def test_missing_python_fails_before_any_target_write(self) -> None:
        installer = self.installer()
        pythonless = PythonlessPath(self.root / "pythonless tools")
        installer.environment["PATH"] = str(pythonless.directory)
        before = tree_signature(self.root)
        result = installer.run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("python3 absent", result.stderr)
        self.assertEqual(before, tree_signature(self.root))

    def test_generic_skill_collision_does_not_apply_instruction_candidate(self) -> None:
        self.seed_canonical(b"original user safety\n", 0o664)
        self.seed_alias()
        (self.claude / "skills/tmux-subagents/SKILL.md").mkdir(parents=True)
        before = tree_signature(self.root)
        result = self.installer().run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("collision", result.stderr)
        self.assertEqual(before, tree_signature(self.root))

    def test_deep_generic_parent_escape_refuses_before_instruction_write(self) -> None:
        self.seed_canonical()
        self.claude.mkdir()
        outside = self.root / "unrelated existing tree"
        (outside / "tmux-subagents").mkdir(parents=True)
        (self.claude / "skills").symlink_to(outside, target_is_directory=True)
        before = tree_signature(self.root)
        result = self.installer().run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("directory ancestry without symlinks", result.stderr)
        self.assertEqual(before, tree_signature(self.root))

    def test_alias_collision_prevents_every_installer_write(self) -> None:
        self.seed_canonical()
        self.alias.parent.mkdir(parents=True)
        self.alias.write_bytes(b"foreign producer's ordinary rules file\n")
        before = tree_signature(self.root)
        result = self.installer().run()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected exact native link", result.stderr)
        self.assertEqual(before, tree_signature(self.root))

    def test_marked_legacy_and_mixed_legacy_never_get_auto_withdrawn(self) -> None:
        self.claude.mkdir()
        legacy = self.claude / "CLAUDE.md"
        for prefix in (b"", b"user policy with no complete-content approval\n"):
            legacy.write_bytes(prefix + self.template)
            legacy.chmod(0o664)
            before = tree_signature(self.root)
            result = self.installer().run()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("native loading proof" if not prefix else "complete-content merge", result.stderr)
            self.assertEqual(before, tree_signature(self.root))

    def test_template_rename_preserves_native_workflow_verbatim(self) -> None:
        previous = (SKILL_ROOT / "references/legacy/instructions/2.0.4.signature").read_bytes()
        guard = (b"Apply this block only when the active harness is Claude Code. Pi uses its native "
                 b"subagent lifecycle, not this Claude-only workflow.\n\n")
        self.assertEqual(self.template.replace(guard, b""), previous)
        self.assertFalse((SKILL_ROOT / "integrations/claude/CLAUDE.addendum.md").exists())

    def test_active_source_selects_renamed_template_and_declares_prerequisite(self) -> None:
        for relative in ("install.sh", "manifest.json", "README.md"):
            text = (SKILL_ROOT / relative).read_text()
            with self.subTest(relative=relative):
                self.assertNotIn("integrations/claude/CLAUDE.addendum.md", text)
                self.assertIn("Python 3.10+", text)
        self.assertIn("AGENTS.addendum.md", (SKILL_ROOT / "install.sh").read_text())
