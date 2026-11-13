"""Refusal wording for the instruction file boundary; no I/O, so messages stay testable."""
from __future__ import annotations

import errno
import sys
from pathlib import Path

from records import Image

# A filesystem or kernel without rename-exchange reports one of these; we then refuse.
EXCHANGE_UNSUPPORTED = frozenset({errno.ENOSYS, errno.EINVAL, errno.ENOTSUP, errno.EOPNOTSUPP})
SWAP_WANTED = "rename-exchange support (renameat2 RENAME_EXCHANGE or renameatx_np RENAME_SWAP)"
MOVE_WANTED = "no-replace rename support (renameat2 RENAME_NOREPLACE or renameatx_np RENAME_EXCL)"
LEFT_IN_PLACE = "the entry now at that name was left in place and nothing was recorded as ours"


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


def refuse_unsupported_rename(failure: OSError, path: Path, device: int, wanted: str) -> None:
    """Raise the fail-closed refusal when the flagged rename is unsupported; e.g. EINVAL.

    Example: any other errno (EIO, EEXIST) returns, so the caller re-raises the original.
    """
    if failure.errno in EXCHANGE_UNSUPPORTED:
        raise unsupported_rename(path, device, wanted, failure) from failure


def describe_image(image: Image) -> str:
    """Name an entry without echoing its content; e.g. kind=regular identity=(…) bytes=12."""
    return (f"kind={image.kind} identity={image.identity} mode={image.mode:#o} "
            f"owner={image.uid}:{image.gid} bytes={len(image.payload)} mtime_ns={image.mtime_ns}")
