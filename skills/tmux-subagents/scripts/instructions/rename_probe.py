"""Prove both atomic flagged renames on scratch entries before the first document write."""
from __future__ import annotations

import contextlib
import errno
import os
from pathlib import Path

from exchange import ExchangeNames
from files import InstructionFiles
from refusals import MOVE_WANTED, SWAP_WANTED, refuse_unsupported_rename, unsupported_rename

# Each proof owns its names, so a rename that misbehaves in one cannot confuse the other.
SWAP_PAIR = (".tmux-agents-probe-swap-a", ".tmux-agents-probe-swap-b")
MOVE_SOURCE, MOVE_OCCUPIED, MOVE_FREE = (".tmux-agents-probe-move-a", ".tmux-agents-probe-move-b",
                                         ".tmux-agents-probe-move-c")
CREATED_NAMES = (*SWAP_PAIR, MOVE_SOURCE, MOVE_OCCUPIED)
# No real entry has inode 0, so it can stand for a name that is absent.
ABSENT_INODE = 0


def prove_renames(files: InstructionFiles, private: Path) -> None:
    """Refuse unless exchange and no-replace rename both work; e.g. prove_renames(files, recovery).

    MIR-891: a filesystem without them used to be found out after documents were written,
    and the run could not undo itself. `private` must be a directory this run just created;
    the scratch entries stay inside it, never in a user directory, and are removed again.
    """
    with files.directory(private) as directory:
        created: list[int] = []
        try:
            create_probe_entries(directory, created)
            refusals = collect_refusals(files, directory, private)
        finally:
            remove_probe_entries(directory, created)
    if refusals:
        raise ValueError("; also ".join(str(refusal) for refusal in refusals)) from refusals[0]


def create_probe_entries(directory: int, created: list[int]) -> None:
    """Create the empty scratch files; e.g. created ends up holding their four inodes."""
    for name in CREATED_NAMES:
        descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=directory)
        with os.fdopen(descriptor, "wb") as stream:
            created.append(os.fstat(stream.fileno()).st_ino)


def remove_probe_entries(directory: int, created: list[int]) -> None:
    """Unlink only entries this probe created; e.g. after a refusal the directory is empty again."""
    for name in (*CREATED_NAMES, MOVE_FREE):
        # Judged by inode: a rename that ignored its flag can leave our file at another name.
        if probe_inode(directory, name) in created:
            os.unlink(name, dir_fd=directory)


def collect_refusals(files: InstructionFiles, directory: int, private: Path) -> list[ValueError]:
    """Run both proofs so one refusal names every missing capability; e.g. [] on ext4."""
    refusals: list[ValueError] = []
    for prove in (prove_exchange, prove_move):
        try:
            prove(files, directory, private)
        except ValueError as refusal:
            refusals.append(refusal)
    return refusals


def prove_exchange(files: InstructionFiles, directory: int, private: Path) -> None:
    """Swap two scratch names and check both inodes moved; e.g. EINVAL becomes the refusal."""
    first, second = probe_inodes(directory, SWAP_PAIR)
    entry = private / SWAP_PAIR[1]
    attempt_rename(files.exchange, directory, SWAP_PAIR, entry, SWAP_WANTED)
    require_probe_inodes(directory, SWAP_PAIR, (second, first), entry, SWAP_WANTED)


def prove_move(files: InstructionFiles, directory: int, private: Path) -> None:
    """Check an occupied name is refused and a free one is taken; e.g. EINVAL becomes the refusal."""
    names = (MOVE_SOURCE, MOVE_OCCUPIED, MOVE_FREE)
    source, occupied, _ = probe_inodes(directory, names)
    entry = private / MOVE_SOURCE
    # A rename that ignores the flag overwrites the occupied name instead of raising EEXIST.
    with contextlib.suppress(FileExistsError):
        attempt_rename(files.move, directory, (MOVE_SOURCE, MOVE_OCCUPIED), entry, MOVE_WANTED)
    require_probe_inodes(directory, names, (source, occupied, ABSENT_INODE), entry, MOVE_WANTED)
    attempt_rename(files.move, directory, (MOVE_SOURCE, MOVE_FREE), entry, MOVE_WANTED)
    require_probe_inodes(directory, names, (ABSENT_INODE, occupied, source), entry, MOVE_WANTED)


def attempt_rename(rename: ExchangeNames, directory: int, names: tuple[str, str], entry: Path,
                   wanted: str) -> None:
    """Call one injected rename, failing closed; e.g. ENOSYS raises the unsupported refusal."""
    try:
        rename(directory, *names)
    except OSError as failure:
        # Fail closed: there is no plain-rename fallback to probe instead.
        refuse_unsupported_rename(failure, entry, os.fstat(directory).st_dev, wanted)
        raise


def require_probe_inodes(directory: int, names: tuple[str, ...], expected: tuple[int, ...],
                         entry: Path, wanted: str) -> None:
    """Refuse when a rename reported success but did something else; e.g. a plain rename."""
    found = probe_inodes(directory, names)
    if found == expected:
        return
    answer = OSError(errno.ENOTSUP, f"probe names={names!r} hold inodes={found!r}; expected "
                                    f"{expected!r}, so the rename flag was not honoured")
    raise unsupported_rename(entry, os.fstat(directory).st_dev, wanted, answer)


def probe_inodes(directory: int, names: tuple[str, ...]) -> tuple[int, ...]:
    """Read where each scratch file is now.

    Example: (12, 13) before a swap and (13, 12) after it.
    """
    return tuple(probe_inode(directory, name) for name in names)


def probe_inode(directory: int, name: str) -> int:
    """Read one name's inode without following links; e.g. ABSENT_INODE for a missing name."""
    try:
        return os.stat(name, dir_fd=directory, follow_symlinks=False).st_ino
    except FileNotFoundError:
        return ABSENT_INODE
