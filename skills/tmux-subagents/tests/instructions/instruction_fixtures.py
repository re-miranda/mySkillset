"""Named filesystem fakes; every writable path belongs to a temporary fixture."""
from __future__ import annotations

import errno
import hashlib
import os
import stat
import sys
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path

SKILL_ROOT = Path(__file__).absolute().parents[2]
sys.path.insert(0, str(SKILL_ROOT / "scripts" / "instructions"))
from exchange import ExchangeNames, MoveWithoutReplace, exchange, move_without_replace
from files import InstructionFiles
from planning import build_plan
from records import Image, Parent, Plan

REAL_FSYNC = os.fsync
LATE_EDIT = b"USER EDIT SAVED AFTER FINAL CHECK\n"
EDITOR_SAVE = b"EDITOR ATOMIC SAVE AFTER FINAL CHECK\n"
SECOND_SAVE = b"SECOND SAVE DURING SWAP BACK\n"
RECREATED = b"FILE CREATED AT THE NAME WHILE THE ENTRY WAS MOVED ASIDE\n"
USER_LINK = "user-own-rules.md"

# A user's save into one name of an open directory; e.g. save_in_place(fd, "AGENTS.md").
LateSave = Callable[[int, str], None]


def save_in_place(directory_fd: int, name: str) -> None:
    """Rewrite the entry through a new descriptor; e.g. a plain editor write of LATE_EDIT."""
    descriptor = os.open(name, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW, dir_fd=directory_fd)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(LATE_EDIT)


def save_by_rename_over(directory_fd: int, name: str) -> None:
    """Write a new file and rename it over the name; e.g. an editor's atomic EDITOR_SAVE."""
    descriptor = os.open("editor-save.tmp", os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                         0o600, dir_fd=directory_fd)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(EDITOR_SAVE)
    os.replace("editor-save.tmp", name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)


def replace_with_user_link(directory_fd: int, name: str) -> None:
    """Swap in the user's own symlink; e.g. the alias now points at USER_LINK."""
    os.symlink(USER_LINK, "user-link.tmp", dir_fd=directory_fd)
    os.replace("user-link.tmp", name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)


def same_directory(directory_fd: int, path: Path) -> bool:
    """Tell the two AGENTS.md parents apart; e.g. the Pi root versus the native rules directory."""
    opened, named = os.fstat(directory_fd), path.stat()
    return (opened.st_dev, opened.st_ino) == (named.st_dev, named.st_ino)


def save_at(path: Path, save: LateSave) -> None:
    """Apply a save to a full path; e.g. save_at(canonical, save_in_place)."""
    directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        save(directory_fd, path.name)
    finally:
        os.close(directory_fd)


class FaultInstructionFiles(InstructionFiles):
    """Inject explicit fixture publication failures, never a production environment bypass."""

    def __init__(self, swap: ExchangeNames = exchange,
                 move: MoveWithoutReplace = move_without_replace) -> None:
        """Use the local fixture owner; e.g. no privileged chown-based tests."""
        super().__init__(os.getuid(), set(os.getgroups()) | {os.getgid()}, os.getgid(), swap,
                         move)
        self.fail_publication: Path | None = None
        self.drift_publication: Path | None = None
        self.fail_alias = False
        self.post_publication_failure: Path | None = None

    def publish(self, path: Path, expected: Image, payload: bytes, mode: int, gid: int,
                mtime_ns: int | None = None) -> Image:
        """Model I/O and concurrent edits; e.g. drift occurs before the production identity guard."""
        if path == self.fail_publication:
            raise OSError(f"fixture write failure at {path}")
        if path == self.drift_publication:
            path.write_bytes(b"concurrent user rules\n")
        result = super().publish(path, expected, payload, mode, gid, mtime_ns)
        if path == self.post_publication_failure:
            raise OSError(f"fixture post-publish failure at {path}")
        return result

    def create_alias(self, path: Path, text: str, restored: Image | None = None) -> Image:
        """Fail the second publication; e.g. canonical recovery must not lose existing rules."""
        if self.fail_alias:
            raise OSError(f"fixture alias failure at {path}")
        return super().create_alias(path, text, restored)


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

    def _stage_at(self, directory: int, name: str, payload: bytes, mode: int, gid: int,
                  mtime_ns: int | None) -> os.stat_result:
        super()._stage_at(directory, name, b"concurrent temporary content", mode, gid, mtime_ns)
        return super()._stage_at(directory, name, payload, mode, gid, mtime_ns)


class SuidClearingFiles(FaultInstructionFiles):
    """Model a kernel that accepts fchmod yet drops setuid/setgid (MIR-696 P2)."""

    def _set_staged_metadata(self, descriptor: int, mode: int, gid: int,
                             mtime_ns: int | None) -> None:
        """Strip the special bits after the real call; e.g. 0o2664 lands as 0o664."""
        super()._set_staged_metadata(descriptor, mode, gid, mtime_ns)
        os.fchmod(descriptor, mode & 0o777)


class LateEditFiles(FaultInstructionFiles):
    """Reviewer's MIR-696 P0 reproduction: an in-place save lands after the final check."""

    def __init__(self, target: Path, swap: ExchangeNames = exchange) -> None:
        """Bind the edited document; e.g. journal publications stay undisturbed."""
        super().__init__(swap)
        self.target = target

    def _publish_at(self, directory: int, temporary: str, path: Path, expected: Image) -> None:
        if path == self.target:
            save_in_place(directory, path.name)
        super()._publish_at(directory, temporary, path, expected)


class RenameOverFiles(FaultInstructionFiles):
    """Model an editor's atomic save: a new file renamed over the name after the final check."""

    def __init__(self, target: Path) -> None:
        """Bind the saved document; e.g. only the canonical AGENTS is replaced."""
        super().__init__()
        self.target = target

    def _publish_at(self, directory: int, temporary: str, path: Path, expected: Image) -> None:
        if path == self.target:
            save_by_rename_over(directory, path.name)
        super()._publish_at(directory, temporary, path, expected)


class SaveBeforeMove:
    """Stand in for the no-replace move: a save lands right before the entry is moved aside."""

    def __init__(self, target: Path, save: LateSave, recreate: bool = False) -> None:
        """Bind the entry and the save; e.g. recreate=True also re-creates the name before the return."""
        self.target = target
        self.save = save
        self.recreate = recreate
        self.saved = False

    def __call__(self, directory_fd: int, source: str, moved_to: str) -> None:
        """Move for real; e.g. the first move of the target is preceded by the save."""
        ours = same_directory(directory_fd, self.target.parent)
        if ours and source == self.target.name and not self.saved:
            self.save_now(directory_fd)
        elif ours and moved_to == self.target.name and self.saved and self.recreate:
            Path(self.target).write_bytes(RECREATED)
        move_without_replace(directory_fd, source, moved_to)

    def save_now(self, directory_fd: int) -> None:
        """Save once; e.g. either hook of SaveBeforeRemoveFiles may fire it, never both."""
        self.saved = True
        self.save(directory_fd, self.target.name)


class SaveBeforeRemoveFiles(FaultInstructionFiles):
    """Reviewer's MIR-889 P0 reproduction: a save lands after the last look at the name.

    The reviewer's hook is the by-name snapshot inside remove. remove no longer takes one,
    so the same save is also injected at the latest point left: right before the move aside.
    """

    def __init__(self, target: Path, save: LateSave = save_in_place,
                 recreate: bool = False) -> None:
        """Bind the removed entry; e.g. only the canonical removal is disturbed."""
        self.late = SaveBeforeMove(target, save, recreate)
        super().__init__(move=self.late)
        self.target = target
        self.removing = False

    def remove(self, path: Path, expected: Image) -> None:
        """Arm the snapshot hook for the target's removal only; e.g. the alias goes undisturbed."""
        self.removing = path == self.target
        try:
            super().remove(path, expected)
        finally:
            self.removing = False

    def _snapshot_at(self, directory: int, name: str, limit: int = 1024 * 1024) -> Image:
        image = super()._snapshot_at(directory, name, limit)
        if self.removing and name == self.target.name and not self.late.saved:
            self.late.save_now(directory)
        return image


class SaveAfterPublishFiles(FaultInstructionFiles):
    """Reviewer's MIR-889 P1 reproduction: a save lands right after our file takes the name."""

    def __init__(self, target: Path, save: LateSave = save_in_place) -> None:
        """Bind the published document; e.g. journal publications stay undisturbed."""
        super().__init__()
        self.target = target
        self.save = save

    def _publish_at(self, directory: int, temporary: str, path: Path, expected: Image) -> None:
        super()._publish_at(directory, temporary, path, expected)
        if path == self.target:
            self.save(directory, path.name)


class ReplaceAfterAliasFiles(FaultInstructionFiles):
    """Model the new alias being replaced by the user's own link before it is verified."""

    def __init__(self, target: Path) -> None:
        """Bind the alias; e.g. the canonical's link into place is left alone."""
        super().__init__()
        self.target = target

    def _link_into_place_at(self, directory: int, temporary: str, name: str) -> None:
        super()._link_into_place_at(directory, temporary, name)
        if name == self.target.name and same_directory(directory, self.target.parent):
            replace_with_user_link(directory, name)


class SaveAfterRestoreFiles(FaultInstructionFiles):
    """Model a save that lands right after a rollback restored the document."""

    def __init__(self, target: Path) -> None:
        """Bind the restored document; e.g. saved_mtime_ns records the save's own mtime."""
        super().__init__()
        self.target = target
        self.saved_mtime_ns = 0

    def publish(self, path: Path, expected: Image, payload: bytes, mode: int, gid: int,
                mtime_ns: int | None = None) -> Image:
        """Publish for real, then save; e.g. only the restore, which passes an mtime, is followed."""
        result = super().publish(path, expected, payload, mode, gid, mtime_ns)
        if path == self.target and mtime_ns is not None:
            save_at(path, save_in_place)
            self.saved_mtime_ns = path.lstat().st_mtime_ns
        return result


class UnsupportedExchange:
    """Model a kernel or filesystem without rename-exchange or no-replace rename."""

    def __call__(self, directory_fd: int, first: str, second: str) -> None:
        """Refuse like renameat2 on an unsupporting filesystem.

        Example: any pair of names raises EINVAL and nothing is renamed.
        """
        raise OSError(errno.EINVAL, f"fixture: no exchange for {(first, second)!r}")


class FailingSwapBackExchange:
    """Let the first swap through, then fail every later one."""

    def __init__(self) -> None:
        """Count swaps so only the first succeeds.

        Example: call 1 publishes, call 2 is the swap back.
        """
        self.calls = 0

    def __call__(self, directory_fd: int, first: str, second: str) -> None:
        """Swap once for real; e.g. the swap back then raises EIO."""
        self.calls += 1
        if self.calls > 1:
            raise OSError(errno.EIO, f"fixture: swap back failed for {(first, second)!r}")
        exchange(directory_fd, first, second)


class SecondSaveExchange:
    """Model a second in-place save that lands while our staged file holds the name."""

    def __init__(self) -> None:
        """Count swaps to time the injected save.

        Example: the save is injected right before the swap back, call 2.
        """
        self.calls = 0

    def __call__(self, directory_fd: int, first: str, second: str) -> None:
        """Swap for real; e.g. before call 2 the destination name is rewritten in place."""
        self.calls += 1
        if self.calls == 2:
            descriptor = os.open(second, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW,
                                 dir_fd=directory_fd)
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(SECOND_SAVE)
        exchange(directory_fd, first, second)


class SameTickSecondSaveExchange:
    """Model a second save of the same size in the same clock tick as our staging write."""

    def __init__(self) -> None:
        """Count swaps to time the injected save.

        Example: the save is injected right before the swap back, call 2.
        """
        self.calls = 0

    def __call__(self, directory_fd: int, first: str, second: str) -> None:
        """Swap for real; e.g. before call 2 the name is rewritten keeping size and mtime."""
        self.calls += 1
        if self.calls == 2:
            staged = os.stat(second, dir_fd=directory_fd, follow_symlinks=False)
            descriptor = os.open(second, os.O_WRONLY | os.O_NOFOLLOW, dir_fd=directory_fd)
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(b"S" * staged.st_size)
            os.utime(second, ns=(staged.st_atime_ns, staged.st_mtime_ns), dir_fd=directory_fd)
        exchange(directory_fd, first, second)


class RenameOverSwapBackExchange:
    """Model a second save by editor rename-over while our staged file holds the name."""

    def __init__(self) -> None:
        """Count swaps to time the injected rename-over.

        Example: the new file replaces the name right before the swap back, call 2.
        """
        self.calls = 0

    def __call__(self, directory_fd: int, first: str, second: str) -> None:
        """Swap for real; e.g. before call 2 a fresh file is renamed over the destination."""
        self.calls += 1
        if self.calls == 2:
            descriptor = os.open("editor-second.tmp", os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                                 0o600, dir_fd=directory_fd)
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(SECOND_SAVE)
            os.replace("editor-second.tmp", second, src_dir_fd=directory_fd,
                       dst_dir_fd=directory_fd)
        exchange(directory_fd, first, second)


class FailingNextSync:
    """Stand in for os.fsync: fail once when armed, otherwise sync for real (MIR-887)."""

    def __init__(self) -> None:
        """Start disarmed so earlier syncs are real.

        Example: staging syncs pass until the swap back arms the fault.
        """
        self.armed = False

    def __call__(self, descriptor: int) -> None:
        """Raise EIO for the first sync after arming; e.g. the directory sync after swap back."""
        if not self.armed:
            REAL_FSYNC(descriptor)
            return
        self.armed = False
        raise OSError(errno.EIO, f"fixture: sync failed for descriptor={descriptor}")


class UnsyncedSwapBackExchange:
    """Do both swaps for real, then make the sync that follows the swap back fail."""

    def __init__(self, sync: FailingNextSync) -> None:
        """Bind the sync fake to arm; e.g. call 2 is the swap back."""
        self.calls = 0
        self.sync = sync

    def __call__(self, directory_fd: int, first: str, second: str) -> None:
        """Swap for real; e.g. after call 2 the next os.fsync raises EIO."""
        self.calls += 1
        exchange(directory_fd, first, second)
        self.sync.armed = self.calls == 2


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


def signature_without_directory_mtimes(root: Path) -> dict[str, tuple[object, ...]]:
    """Compare a tree across a refused run; e.g. equal before and after means no trace.

    MIR-892: the one stated exception to `tree_signature` is the mtime of a directory,
    which truthfully shows that the run created and removed entries in it. Existence,
    type, mode, owner, inode and content of every entry, and the mtime of every file
    and link, still count.
    """
    result = tree_signature(root)
    for name, entry in result.items():
        if stat.S_ISDIR((root / name).lstat().st_mode):
            result[name] = (*entry[:4], None, entry[5])
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

    def scratch_names(self) -> list[str]:
        """List leftover staging or conflict entries beside the document.

        Example: [] after a clean refusal, one conflict name after a failed swap back.
        """
        return sorted(path.name for path in self.pi.glob(".tmux-agents-*"))

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
