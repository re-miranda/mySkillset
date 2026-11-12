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

from exchange import ExchangeNames
from records import Image, Parent

PUBLISH_LIMIT = 16 * 1024 * 1024
# A filesystem or kernel without rename-exchange reports one of these; we then refuse.
EXCHANGE_UNSUPPORTED = frozenset({errno.ENOSYS, errno.EINVAL, errno.ENOTSUP, errno.EOPNOTSUPP})


class InstructionFiles:
    """Own narrow document I/O; e.g. never inspect a client's settings/auth directory."""

    def __init__(self, uid: int, groups: set[int], primary_gid: int,
                 exchange: ExchangeNames) -> None:
        """Inject identity and the atomic swap; e.g. fixtures pass their owner and a fault fake."""
        self.uid = uid
        self.groups = groups
        self.primary_gid = primary_gid
        self.exchange = exchange
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

    def publish(self, path: Path, expected: Image, payload: bytes, mode: int, gid: int) -> Image:
        """Publish without destroying a concurrent save; e.g. never open the native alias for writes."""
        with self.directory(path.parent) as directory:
            # Early refusal only; the binding check is on the displaced entry after the swap.
            self._require_image_at(directory, path, expected)
            temporary = ".tmux-agents-" + secrets.token_hex(12)
            staged = self._stage_at(directory, temporary, payload, mode, gid)
            try:
                self._publish_at(directory, temporary, path, expected)
                os.fsync(directory)
                return self._snapshot_at(directory, path.name, PUBLISH_LIMIT)
            finally:
                self._remove_temporary(directory, temporary, staged)

    def _require_image_at(self, directory: int, path: Path, expected: Image) -> None:
        current = self._snapshot_at(directory, path.name, PUBLISH_LIMIT)
        if current != expected:
            raise ValueError(f"entry={str(path)!r} {describe_image(current)}; "
                             f"expected unchanged preflight image {describe_image(expected)}")

    def _stage_at(self, directory: int, name: str, payload: bytes, mode: int, gid: int) -> os.stat_result:
        descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=directory)
        try:
            self._write_staged(descriptor, payload)
            self._set_staged_metadata(descriptor, mode, gid)
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

    def _set_staged_metadata(self, descriptor: int, mode: int, gid: int) -> None:
        # Order is load-bearing (MIR-696 P2): an unprivileged write and any chown both
        # clear setuid/setgid on Linux, so the mode goes on last, after the payload.
        os.fchown(descriptor, self.uid, gid)
        os.fchmod(descriptor, mode)
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
        # link refuses an existing name (EEXIST), so an absent destination has no overwrite race.
        os.link(temporary, path.name, src_dir_fd=directory, dst_dir_fd=directory,
                follow_symlinks=False)
        os.unlink(temporary, dir_fd=directory)

    def _swap_verified_at(self, directory: int, temporary: str, path: Path, expected: Image) -> None:
        # rename cannot inspect what it overwrites (MIR-696 P0): swap, then judge what came out.
        self._exchange_or_refuse(directory, temporary, path)
        try:
            self._require_displaced_at(directory, temporary, expected)
        except (OSError, ValueError) as conflict:
            kept = self._return_displaced_at(directory, temporary, path)
            raise ValueError(f"entry={str(path)!r}; {conflict}; concurrent version "
                             f"preserved at {str(kept)!r}, nothing published") from conflict
        # Safe to drop: its bytes equal the recorded before-state held in recovery.
        os.unlink(temporary, dir_fd=directory)

    def _exchange_or_refuse(self, directory: int, temporary: str, path: Path) -> None:
        try:
            self.exchange(directory, temporary, path.name)
        except OSError as failure:
            if failure.errno not in EXCHANGE_UNSUPPORTED:
                raise
            # Fail closed: no os.replace fallback, which would reopen the overwrite race.
            raise ValueError(
                f"entry={str(path)!r} platform={sys.platform!r} "
                f"filesystem device={os.fstat(directory).st_dev}; expected atomic rename-exchange "
                f"support (renameat2 RENAME_EXCHANGE or renameatx_np RENAME_SWAP), got {failure}; "
                "destination left untouched") from failure

    def _require_displaced_at(self, directory: int, temporary: str, expected: Image) -> None:
        displaced = self._snapshot_at(directory, temporary, PUBLISH_LIMIT)
        if settled_image(displaced) != settled_image(expected):
            raise ValueError(f"displaced {describe_image(displaced)}; "
                             f"expected {describe_image(expected)}")

    def _return_displaced_at(self, directory: int, temporary: str, path: Path) -> Path:
        try:
            self.exchange(directory, temporary, path.name)
            os.fsync(directory)
            return path
        except OSError:
            return path.with_name(self._keep_conflict_at(directory, temporary))

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

    def _remove_temporary(self, directory: int, name: str, expected: os.stat_result) -> None:
        try:
            current = os.stat(name, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            return
        # Size and mtime too: a save that landed in our staged file while it held the
        # destination name must survive cleanup after a swap back.
        if staged_identity(current) == staged_identity(expected):
            os.unlink(name, dir_fd=directory)

    def create_alias(self, path: Path, text: str) -> Image:
        """Create a missing link without replacement; e.g. refuse a late collision."""
        with self.directory(path.parent) as descriptor:
            os.symlink(text, path.name, dir_fd=descriptor)
            os.fsync(descriptor)
        return self.snapshot(path)

    def remove(self, path: Path, expected: Image) -> None:
        """Remove only this transaction's after-state; e.g. rollback a newly created alias."""
        with self.directory(path.parent) as descriptor:
            if self._snapshot_at(descriptor, path.name) != expected:
                raise ValueError(f"entry={str(path)!r}; expected transaction after-state before unlink")
            os.unlink(path.name, dir_fd=descriptor)
            os.fsync(descriptor)

    def restore_metadata(self, path: Path, before: Image) -> None:
        """Restore group and mtime; e.g. recreated native links retain recorded metadata."""
        with self.directory(path.parent) as descriptor:
            current = os.stat(path.name, dir_fd=descriptor, follow_symlinks=False)
            if current.st_gid != before.gid:
                os.chown(path.name, -1, before.gid, dir_fd=descriptor, follow_symlinks=False)
            os.utime(path.name, ns=(before.mtime_ns, before.mtime_ns), dir_fd=descriptor,
                     follow_symlinks=False)
            os.fsync(descriptor)

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


def staged_identity(info: os.stat_result) -> tuple[int, ...]:
    """Recognize our untouched scratch file; e.g. renames change ctime, a later write changes mtime."""
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)


def settled_image(image: Image) -> Image:
    """Drop ctime, which the swap itself advances; e.g. compare a displaced inode with its preflight."""
    return replace(image, identity=image.identity[:3])


def describe_image(image: Image) -> str:
    """Name an entry without echoing its content; e.g. kind=regular identity=(…) bytes=12."""
    return (f"kind={image.kind} identity={image.identity} mode={image.mode:#o} "
            f"owner={image.uid}:{image.gid} bytes={len(image.payload)} mtime_ns={image.mtime_ns}")
