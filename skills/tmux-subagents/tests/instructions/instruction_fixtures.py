"""Named filesystem fakes; every writable path belongs to a temporary fixture."""
from __future__ import annotations

import hashlib
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

SKILL_ROOT = Path(__file__).absolute().parents[2]
sys.path.insert(0, str(SKILL_ROOT / "scripts" / "instructions"))
from files import InstructionFiles
from planning import build_plan
from records import Image, Parent, Plan


class FaultInstructionFiles(InstructionFiles):
    """Inject explicit fixture publication failures, never a production environment bypass."""

    def __init__(self) -> None:
        """Use the local fixture owner; e.g. no privileged chown-based tests."""
        super().__init__(os.getuid(), set(os.getgroups()) | {os.getgid()}, os.getgid())
        self.fail_publication: Path | None = None
        self.drift_publication: Path | None = None
        self.fail_alias = False
        self.post_publication_failure: Path | None = None

    def publish(self, path: Path, expected: Image, payload: bytes, mode: int, gid: int) -> Image:
        """Model I/O and concurrent edits; e.g. drift occurs before the production identity guard."""
        if path == self.fail_publication:
            raise OSError(f"fixture write failure at {path}")
        if path == self.drift_publication:
            path.write_bytes(b"concurrent user rules\n")
        result = super().publish(path, expected, payload, mode, gid)
        if path == self.post_publication_failure:
            raise OSError(f"fixture post-publish failure at {path}")
        return result

    def create_alias(self, path: Path, text: str) -> Image:
        """Fail the second publication; e.g. canonical recovery must not lose existing rules."""
        if self.fail_alias:
            raise OSError(f"fixture alias failure at {path}")
        return super().create_alias(path, text)


class DeniedParentFiles(FaultInstructionFiles):
    """Model unwriteable parents without chmod or privilege-dependent test outcomes."""

    def __init__(self, denied: Path) -> None:
        """Bind one denied parent; e.g. a preexisting recovery directory."""
        super().__init__()
        self.denied = denied

    def can_write(self, path: Path) -> bool:
        """Inject the filesystem access decision; e.g. preflight must reject before mkdir."""
        permitted = path != self.denied and super().can_write(path)
        return permitted


class ForeignProfileParentFiles(FaultInstructionFiles):
    """Model a foreign-owned native root, separately from trusted system ancestors."""

    def __init__(self, foreign: Path) -> None:
        """Bind the substituted directory; e.g. a wrong-owner configured Pi root."""
        super().__init__()
        self.foreign = foreign

    def parent(self, path: Path) -> Parent:
        """Project the changed owner; e.g. the profile-role gate must reject it."""
        actual = super().parent(path)
        if path != self.foreign:
            return actual
        token = actual.identity[:2] + (self.uid + 1,) + actual.identity[3:]
        return Parent(path, token)


class CollidingStageFiles(FaultInstructionFiles):
    """Model a late scratch-name collision without granting cleanup ownership."""

    def _stage_at(self, directory: int, name: str, payload: bytes, mode: int,
                  gid: int) -> os.stat_result:
        super()._stage_at(directory, name, b"concurrent temporary content", mode, gid)
        return super()._stage_at(directory, name, payload, mode, gid)


def tree_signature(root: Path) -> dict[str, tuple[object, ...]]:
    """Ignore read-only atime changes; e.g. detect any target content/mode/mtime mutation."""
    result: dict[str, tuple[object, ...]] = {}
    for path in (root, *sorted(root.rglob("*"))):
        info = path.lstat()
        content = path.readlink().as_posix() if path.is_symlink() else ""
        if stat.S_ISREG(info.st_mode):
            content = hashlib.sha256(path.read_bytes()).hexdigest()
        result[str(path.relative_to(root))] = (info.st_mode, info.st_uid, info.st_gid,
                                              info.st_ino, info.st_mtime_ns, content)
    return result


class InstructionFixture(unittest.TestCase):
    """Provide isolated homes and actual filesystem assertions; e.g. never default to real HOME."""

    def setUp(self) -> None:
        """Seed only temporary roots; e.g. exercise configured paths with spaces."""
        temporary = tempfile.TemporaryDirectory(prefix="tmux-instruction-fixture-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "fixture home"
        self.root.mkdir(mode=0o700)
        self.pi = self.root / "pi agent"
        self.claude = self.root / "claude config"
        self.canonical = self.pi / "AGENTS.md"
        self.alias = self.claude / "rules" / "AGENTS.md"
        self.template = (SKILL_ROOT / "integrations/claude/AGENTS.addendum.md").read_bytes()
        self.files = FaultInstructionFiles()

    def seed_canonical(self, payload: bytes = b"user safety\n", mode: int = 0o664) -> None:
        """Create a known before-state; e.g. migrated files retain 0664 rather than being tightened."""
        self.pi.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.canonical.write_bytes(payload)
        self.canonical.chmod(mode)

    def seed_alias(self, text: str | None = None) -> None:
        """Create an explicit native entry; e.g. its inode/link/mtime must survive updates."""
        self.alias.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        expected = os.path.relpath(self.canonical, self.alias.parent)
        self.alias.symlink_to(expected if text is None else text)

    def plan(self) -> Plan:
        """Exercise real admission; e.g. fixture defaults are never inferred from caller HOME."""
        return build_plan(
            self.pi, self.claude, self.template, self.files)
