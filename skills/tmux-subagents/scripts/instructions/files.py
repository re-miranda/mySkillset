"""POSIX no-follow boundary, injectable into the instruction planner/transaction."""
from __future__ import annotations

import contextlib
import errno
import os
import secrets
import stat
import sys
from collections.abc import Iterator
from dataclasses import replace
from pathlib import Path

from exchange import ExchangeNames, MoveWithoutReplace
from records import Image, Parent

PUBLISH_LIMIT = 16 * 1024 * 1024
# A filesystem or kernel without rename-exchange reports one of these; we then refuse.
EXCHANGE_UNSUPPORTED = frozenset({errno.ENOSYS, errno.EINVAL, errno.ENOTSUP, errno.EOPNOTSUPP})
SWAP_WANTED = "rename-exchange support (renameat2 RENAME_EXCHANGE or renameatx_np RENAME_SWAP)"
MOVE_WANTED = "no-replace rename support (renameat2 RENAME_NOREPLACE or renameatx_np RENAME_EXCL)"
LEFT_IN_PLACE = "the entry now at that name was left in place and nothing was recorded as ours"


class InstructionFiles:
    """Own narrow document I/O; e.g. never inspect a client's settings/auth directory."""

    def __init__(self, uid: int, groups: set[int], primary_gid: int,
                 exchange: ExchangeNames, move: MoveWithoutReplace) -> None:
        """Inject identity and the atomic renames; e.g. fixtures pass their owner and fault fakes."""
        self.uid = uid
        self.groups = groups
        self.primary_gid = primary_gid
        self.exchange = exchange
        self.move = move
        required = ("O_NOFOLLOW", "O_DIRECTORY", "listxattr")
        if os.name != "posix" or not all(hasattr(os, name) for name in required):
            raise ValueError(f"platform={os.name!r}; expected POSIX no-follow and metadata support")

    @contextlib.contextmanager
    def directory(self, path: Path) -> Iterator[int]:
        """Anchor each component without following links; e.g. canonical's parent."""
        descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
        try:
            for component in path.absolute().parts[1:]:
                next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                  dir_fd=descriptor)
                os.close(descriptor)
                descriptor = next_fd
            yield descriptor
        finally:
            os.close(descriptor)

    def snapshot(self, path: Path, limit: int = 1024 * 1024) -> Image:
        """Capture a bounded ordinary document; e.g. lstat never follows the alias."""
        try:
            with self.directory(path.parent) as descriptor:
                return self._snapshot_at(descriptor, path.name, limit)
        except FileNotFoundError:
            return Image("absent")

    def _snapshot_at(self, directory: int, name: str, limit: int = 1024 * 1024) -> Image:
        try:
            info = os.stat(name, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            return Image("absent")
        if info.st_uid != self.uid or info.st_nlink != 1:
            raise ValueError(f"entry={name!r}; expected owned single-link instruction entry")
        identity = (info.st_dev, info.st_ino, info.st_nlink, info.st_ctime_ns)
        common = {"mode": stat.S_IMODE(info.st_mode), "uid": info.st_uid,
                  "gid": info.st_gid, "identity": identity, "mtime_ns": info.st_mtime_ns}
        if stat.S_ISLNK(info.st_mode):
            return Image("link", link=os.readlink(name, dir_fd=directory), **common)
        if not stat.S_ISREG(info.st_mode) or info.st_gid not in self.groups:
            raise ValueError(f"entry={name!r}; expected regular instruction file with preservable group")
        return Image("regular", payload=self._read_at(directory, name, info, limit), **common)

    def _read_at(self, directory: int, name: str, expected: os.stat_result, limit: int) -> bytes:
        descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
        try:
            if stable_stat(os.fstat(descriptor)) != stable_stat(expected) or os.listxattr(descriptor):
                raise ValueError(f"entry={name!r}; expected stable regular file without unhandled attributes")
            with os.fdopen(descriptor, "rb", closefd=False) as stream:
                payload = stream.read(limit + 1)
            if len(payload) > limit or stable_stat(os.fstat(descriptor)) != stable_stat(expected):
                raise ValueError(f"entry={name!r}; expected stable instruction document <={limit} bytes")
            return payload
        finally:
            os.close(descriptor)

    def parents(self, paths: tuple[Path, ...]) -> tuple[tuple[Parent, ...], tuple[Path, ...]]:
        """Bind real parent identities; e.g. reject a symlinked configured root."""
        existing: dict[Path, Parent] = {}
        missing: set[Path] = set()
        ancestry = {parent for target in paths for parent in (target.parent, *target.parent.parents)}
        for path in sorted(ancestry):
            try:
                existing[path] = self.parent(path)
            except FileNotFoundError:
                missing.add(path)
        return tuple(existing.values()), tuple(sorted(missing, key=lambda path: len(path.parts)))

    def parent(self, path: Path) -> Parent:
        """Reject escaped/foreign parents; e.g. root-owned sticky /tmp is valid for fixtures."""
        with self.directory(path) as descriptor:
            info = os.fstat(descriptor)
        if info.st_uid not in {0, self.uid}:
            raise ValueError(f"parent={str(path)!r}; expected executing owner or system ancestor")
        if info.st_uid != self.uid and info.st_mode & 0o022 and not info.st_mode & stat.S_ISVTX:
            raise ValueError(f"parent={str(path)!r}; expected non-writable or sticky system ancestor")
        return Parent(path, (info.st_dev, info.st_ino, info.st_uid, info.st_gid,
                             stat.S_IMODE(info.st_mode)))

    def verify_parents(self, parents: tuple[Parent, ...]) -> None:
        """Detect parent replacement; e.g. drift between planning and publication."""
        for parent in parents:
            if self.parent(parent.path) != parent:
                raise ValueError(f"parent={str(parent.path)!r}; expected preflight directory identity")

    def can_write(self, path: Path) -> bool:
        """Admit the closest existing parent; e.g. reject a read-only recovery directory in preflight."""
        writable = os.access(path, os.W_OK | os.X_OK)
        return writable

    def make_directory(self, path: Path) -> None:
        """Create only a planned private directory; e.g. native rules or recovery."""
        with self.directory(path.parent) as descriptor:
            os.mkdir(path.name, 0o700, dir_fd=descriptor)
            os.fsync(descriptor)
        if self.parent(path).identity[2] != self.uid:
            raise ValueError(f"parent={str(path)!r}; expected newly created owned directory")

    def publish(self, path: Path, expected: Image, payload: bytes, mode: int, gid: int,
                mtime_ns: int | None = None) -> Image:
        """Publish without destroying a concurrent save; e.g. never open the native alias for writes."""
        # A rollback passes the recorded mtime_ns; it is set on the staged file (MIR-889).
        with self.directory(path.parent) as directory:
            # Early refusal only; the binding check is on the displaced entry after the swap.
            self._require_image_at(directory, path, expected)
            temporary = ".tmux-agents-" + secrets.token_hex(12)
            staged = self._stage_at(directory, temporary, payload, mode, gid, mtime_ns)
            try:
                self._publish_at(directory, temporary, path, expected)
                os.fsync(directory)
                return self._require_own_at(directory, path, staged, ("regular", payload, ""))
            except (OSError, ValueError) as failure:
                self._refuse_naming_stranded_at(directory, temporary, (staged, payload), path, failure)
                raise
            finally:
                self._remove_temporary(directory, temporary, staged, payload)

    def _refuse_naming_stranded_at(self, directory: int, temporary: str,
                                   staged: tuple[os.stat_result, bytes], path: Path,
                                   failure: Exception) -> None:
        # MIR-887: cleanup keeps any entry that is not our untouched staged file (it can be
        # a user's newest save), so the failure has to say where that entry is.
        stranded = path.with_name(temporary)
        kept = self._remove_temporary(directory, temporary, *staged)
        if not kept or repr(str(stranded)) in str(failure):
            return
        raise ValueError(f"{failure}; entry kept at {str(stranded)!r} may hold a later save; "
                         "expected only our untouched staged file there, so it was not "
                         "removed") from failure

    def _require_image_at(self, directory: int, path: Path, expected: Image) -> None:
        current = self._snapshot_at(directory, path.name, PUBLISH_LIMIT)
        if current != expected:
            raise ValueError(f"entry={str(path)!r} {describe_image(current)}; "
                             f"expected unchanged preflight image {describe_image(expected)}")

    def _stage_at(self, directory: int, name: str, payload: bytes, mode: int, gid: int,
                  mtime_ns: int | None) -> os.stat_result:
        descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=directory)
        try:
            self._write_staged(descriptor, payload)
            self._set_staged_metadata(descriptor, mode, gid, mtime_ns)
            return self._require_staged_metadata(descriptor, name, mode, gid)
        except (OSError, ValueError):
            self._remove_temporary(directory, name, os.fstat(descriptor))
            raise
        finally:
            os.close(descriptor)

    def _write_staged(self, descriptor: int, payload: bytes) -> None:
        with os.fdopen(descriptor, "wb", closefd=False) as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(descriptor)

    def _set_staged_metadata(self, descriptor: int, mode: int, gid: int,
                             mtime_ns: int | None) -> None:
        # Order is load-bearing (MIR-696 P2): an unprivileged write and any chown both
        # clear setuid/setgid on Linux, so the mode goes on last, after the payload.
        os.fchown(descriptor, self.uid, gid)
        os.fchmod(descriptor, mode)
        # MIR-889: a restored mtime goes on the descriptor; a by-name utime after the swap
        # could land on a later save instead of our file.
        if mtime_ns is not None:
            os.utime(descriptor, ns=(mtime_ns, mtime_ns))
        os.fsync(descriptor)

    def _require_staged_metadata(self, descriptor: int, name: str, mode: int,
                                 gid: int) -> os.stat_result:
        # fchmod can succeed yet drop setgid (group outside the caller's groups), so only
        # the observed state counts; checked before the swap, nothing is published on refusal.
        staged = os.fstat(descriptor)
        observed = (stat.S_IMODE(staged.st_mode), staged.st_uid, staged.st_gid)
        if observed != (mode, self.uid, gid):
            raise ValueError(
                f"staged={name!r} mode={observed[0]:#o} owner={observed[1]}:{observed[2]}; "
                f"expected {mode:#o} owner={self.uid}:{gid} before publication, nothing published")
        return staged

    def _publish_at(self, directory: int, temporary: str, path: Path, expected: Image) -> None:
        if expected.kind == "regular":
            self._swap_verified_at(directory, temporary, path, expected)
            return
        if expected.kind != "absent":
            raise ValueError(f"kind={expected.kind!r}; expected absent or regular canonical destination")
        self._link_into_place_at(directory, temporary, path.name)

    def _link_into_place_at(self, directory: int, temporary: str, name: str) -> None:
        # link refuses an existing name (EEXIST), so an absent destination has no overwrite race.
        os.link(temporary, name, src_dir_fd=directory, dst_dir_fd=directory,
                follow_symlinks=False)
        os.unlink(temporary, dir_fd=directory)

    def _require_own_at(self, directory: int, path: Path, staged: os.stat_result,
                        content: tuple[str, bytes, str]) -> Image:
        # MIR-889 P1: whatever occupies the name is not ours until proven; a save that
        # landed after the swap stays in place and is never recorded as installer output.
        wanted = (f"our staged entry device={staged.st_dev} inode={staged.st_ino} "
                  f"bytes={staged.st_size} mtime_ns={staged.st_mtime_ns}")
        try:
            found = self._snapshot_at(directory, path.name, PUBLISH_LIMIT)
        except ValueError as unreadable:
            raise ValueError(f"entry={str(path)!r}; {unreadable}; expected {wanted}; "
                             f"{LEFT_IN_PLACE}") from unreadable
        observed = (found.identity[:2], found.mtime_ns, (found.kind, found.payload, found.link))
        if observed != ((staged.st_dev, staged.st_ino), staged.st_mtime_ns, content):
            raise ValueError(f"entry={str(path)!r} {describe_image(found)}; "
                             f"expected {wanted}; {LEFT_IN_PLACE}")
        return found

    def _swap_verified_at(self, directory: int, temporary: str, path: Path, expected: Image) -> None:
        # rename cannot inspect what it overwrites (MIR-696 P0): swap, then judge what came out.
        self._exchange_or_refuse(directory, temporary, path)
        try:
            self._require_displaced_at(directory, temporary, expected)
        except (OSError, ValueError) as conflict:
            kept = self._return_displaced_at(directory, temporary, path)
            raise ValueError(f"entry={str(path)!r}; {conflict}; {swap_refusal_outcome(path, kept)}"
                             f"{self._unsynced_note_at(directory)}") from conflict
        # Safe to drop: its bytes equal the recorded before-state held in recovery.
        os.unlink(temporary, dir_fd=directory)

    def _exchange_or_refuse(self, directory: int, temporary: str, path: Path) -> None:
        try:
            self.exchange(directory, temporary, path.name)
        except OSError as failure:
            if failure.errno not in EXCHANGE_UNSUPPORTED:
                raise
            # Fail closed: no os.replace fallback, which would reopen the overwrite race.
            raise unsupported_rename(path, os.fstat(directory).st_dev, SWAP_WANTED,
                                     failure) from failure

    def _require_displaced_at(self, directory: int, temporary: str, expected: Image) -> None:
        displaced = self._snapshot_at(directory, temporary, PUBLISH_LIMIT)
        if settled_image(displaced) != settled_image(expected):
            raise ValueError(f"displaced {describe_image(displaced)}; "
                             f"expected {describe_image(expected)}")

    def _return_displaced_at(self, directory: int, temporary: str, path: Path) -> Path:
        # MIR-887: only a failed swap back means the displaced version is still at the
        # scratch name; after a successful one that name holds our staged file again.
        try:
            self.exchange(directory, temporary, path.name)
        except OSError:
            return path.with_name(self._keep_conflict_at(directory, temporary))
        return path

    def _unsynced_note_at(self, directory: int) -> str:
        # A failed sync is reported, never allowed to change which path the error names.
        try:
            os.fsync(directory)
        except OSError as failure:
            return (f"; directory sync failed ({failure}), expected the preserved entry to "
                    "be durable, so it may not survive a crash")
        return ""

    def _keep_conflict_at(self, directory: int, temporary: str) -> str:
        # Never unlink the displaced version; a stable name tells it apart from scratch files.
        conflict = ".tmux-agents-conflict-" + secrets.token_hex(12)
        try:
            os.link(temporary, conflict, src_dir_fd=directory, dst_dir_fd=directory,
                    follow_symlinks=False)
            os.unlink(temporary, dir_fd=directory)
            return conflict
        except OSError:
            return temporary

    def _remove_temporary(self, directory: int, name: str, expected: os.stat_result,
                          payload: bytes | None = None) -> bool:
        # Returns whether an entry was kept at the name, so a failure can report it (MIR-887).
        try:
            untouched = self._is_untouched_staged_at(directory, name, expected, payload)
        except FileNotFoundError:
            return False
        if not untouched:
            return True
        os.unlink(name, dir_fd=directory)
        return False

    def _is_untouched_staged_at(self, directory: int, name: str, expected: os.stat_result,
                                payload: bytes | None) -> bool:
        # Size and mtime too: a save that landed in our staged file while it held the
        # destination name must survive cleanup after a swap back. The clock is coarse, so
        # a same-size save in the same tick is told apart only by its bytes (MIR-890).
        current = os.stat(name, dir_fd=directory, follow_symlinks=False)
        if staged_identity(current) != staged_identity(expected):
            return False
        if payload is None:
            return True
        descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
        with os.fdopen(descriptor, "rb") as stream:
            return stream.read(len(payload) + 1) == payload

    def create_alias(self, path: Path, text: str, restored: Image | None = None) -> Image:
        """Create a missing link without replacement; e.g. refuse a late collision.

        Example: create_alias(alias, "../pi/AGENTS.md", before) also restores before's group
        and mtime on the scratch link, so nothing touches the name after it is published.
        """
        with self.directory(path.parent) as directory:
            scratch = ".tmux-agents-" + secrets.token_hex(12)
            os.symlink(text, scratch, dir_fd=directory)
            staged = self._stamp_link_at(directory, scratch, restored)
            try:
                self._link_into_place_at(directory, scratch, path.name)
                os.fsync(directory)
                return self._require_own_at(directory, path, staged, ("link", b"", text))
            finally:
                self._remove_temporary(directory, scratch, staged)

    def _stamp_link_at(self, directory: int, scratch: str,
                       restored: Image | None) -> os.stat_result:
        # MIR-889: metadata is set while the link still has our scratch name; a by-name
        # chown or utime after publication could land on a later entry instead.
        try:
            if restored is not None:
                os.chown(scratch, -1, restored.gid, dir_fd=directory, follow_symlinks=False)
                os.utime(scratch, ns=(restored.mtime_ns, restored.mtime_ns), dir_fd=directory,
                         follow_symlinks=False)
            return os.stat(scratch, dir_fd=directory, follow_symlinks=False)
        except OSError:
            os.unlink(scratch, dir_fd=directory)
            raise

    def remove(self, path: Path, expected: Image) -> None:
        """Remove only this transaction's after-state; e.g. rollback a newly created alias."""
        with self.directory(path.parent) as directory:
            scratch = ".tmux-agents-" + secrets.token_hex(12)
            # MIR-889 P0: a check by name cannot guard an unlink by name, so the entry is
            # moved aside first and only the entry we moved is judged and removed.
            self._move_aside_or_refuse(directory, path, scratch)
            try:
                self._require_displaced_at(directory, scratch, expected)
            except (OSError, ValueError) as conflict:
                kept = self._return_moved_at(directory, scratch, path)
                raise ValueError(f"entry={str(path)!r}; {conflict}; "
                                 f"{removal_refusal_outcome(path, kept)}"
                                 f"{self._unsynced_note_at(directory)}") from conflict
            os.unlink(scratch, dir_fd=directory)
            os.fsync(directory)

    def _move_aside_or_refuse(self, directory: int, path: Path, scratch: str) -> None:
        try:
            self.move(directory, path.name, scratch)
        except FileNotFoundError as gone:
            raise ValueError(f"entry={str(path)!r} is absent; expected the transaction "
                             "after-state to remove, nothing removed") from gone
        except OSError as failure:
            if failure.errno not in EXCHANGE_UNSUPPORTED:
                raise
            # Fail closed: falling back to check-then-unlink would reopen MIR-889 P0.
            raise unsupported_rename(path, os.fstat(directory).st_dev, MOVE_WANTED,
                                     failure) from failure

    def _return_moved_at(self, directory: int, scratch: str, path: Path) -> Path:
        # No-replace again: if the name was re-created meanwhile, both versions are kept.
        try:
            self.move(directory, scratch, path.name)
        except OSError:
            return path.with_name(self._keep_conflict_at(directory, scratch))
        return path

    def remove_directory(self, path: Path, expected: Parent | None) -> None:
        """Remove only an empty recorded directory; e.g. preserve replaced parents on rollback."""
        if self.parent(path) != expected:
            raise ValueError(f"parent={str(path)!r}; expected recorded created-directory identity")
        with self.directory(path.parent) as descriptor:
            os.rmdir(path.name, dir_fd=descriptor)
            os.fsync(descriptor)


def stable_stat(info: os.stat_result) -> tuple[int, ...]:
    """Exclude read-induced atime; e.g. a first baseline read is not concurrent drift."""
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink, info.st_uid, info.st_gid,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def swap_refusal_outcome(path: Path, kept: Path) -> str:
    """Say where each version ended up after a refused swap (MIR-888).

    Example: kept == path reads "... preserved at '/p/AGENTS.md', nothing published"; a
    failed swap back instead names the new payload at path and the conflict entry.
    """
    if kept == path:
        return f"concurrent version preserved at {str(kept)!r}, nothing published"
    # The swap back failed, so claiming "nothing published" would be false here.
    return (f"swap back failed, so the canonical name {str(path)!r} holds the new payload; "
            f"concurrent version preserved at {str(kept)!r}")


def removal_refusal_outcome(path: Path, kept: Path) -> str:
    """Say where each version ended up after a refused removal (MIR-889 P0).

    Example: kept == path reads "... returned to '/p/AGENTS.md', nothing removed"; a
    failed return names both the re-created name and the conflict entry.
    """
    if kept == path:
        return f"it is not the recorded after-state, so it was returned to {str(kept)!r}, nothing removed"
    return (f"it is not the recorded after-state and could not be returned without overwriting; "
            f"the name {str(path)!r} keeps whatever occupies it now and the moved version is "
            f"preserved at {str(kept)!r}, nothing removed")


def unsupported_rename(path: Path, device: int, wanted: str, failure: OSError) -> ValueError:
    """Build the fail-closed refusal; e.g. a filesystem whose renameat2 rejects flags (EINVAL)."""
    return ValueError(f"entry={str(path)!r} platform={sys.platform!r} filesystem device={device}; "
                      f"expected atomic {wanted}, got {failure}; entry left untouched")


def staged_identity(info: os.stat_result) -> tuple[int, ...]:
    """Recognize our untouched scratch file.

    Example: renames change ctime and a later write changes mtime, so neither is ours.
    """
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)


def settled_image(image: Image) -> Image:
    """Drop ctime, which the swap itself advances.

    Example: compare a displaced inode with its preflight image.
    """
    return replace(image, identity=image.identity[:3])


def describe_image(image: Image) -> str:
    """Name an entry without echoing its content; e.g. kind=regular identity=(…) bytes=12."""
    return (f"kind={image.kind} identity={image.identity} mode={image.mode:#o} "
            f"owner={image.uid}:{image.gid} bytes={len(image.payload)} mtime_ns={image.mtime_ns}")
