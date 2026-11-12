"""Atomic flagged renames: swap two names, or move to an unused one, never overwriting."""
from __future__ import annotations

import ctypes
import errno
import os
import sys
from collections.abc import Callable

# Injected into InstructionFiles; e.g. tests pass a named fault fake with this shape.
ExchangeNames = Callable[[int, str, str], None]
MoveWithoutReplace = Callable[[int, str, str], None]

# Both calls share one C signature: (int, const char *, int, const char *, unsigned int).
# Linux RENAME_EXCHANGE and macOS RENAME_SWAP are both 0x2.
SWAP_CALLS: dict[str, tuple[str, int]] = {"linux": ("renameat2", 2), "darwin": ("renameatx_np", 2)}
# Linux RENAME_NOREPLACE is 0x1 and macOS RENAME_EXCL is 0x4.
NOREPLACE_CALLS: dict[str, tuple[str, int]] = {"linux": ("renameat2", 1),
                                               "darwin": ("renameatx_np", 4)}


def exchange(directory_fd: int, first: str, second: str, platform: str = sys.platform) -> None:
    """Swap two names in one directory atomically; e.g. exchange(fd, ".staged", "AGENTS.md").

    Plain rename cannot inspect what it overwrites (MIR-696 P0), so callers swap and
    then judge the displaced entry. Unsupported platforms raise ENOTSUP/ENOSYS.
    """
    rename_with_flag(SWAP_CALLS, platform, directory_fd, first, second)


def move_without_replace(directory_fd: int, source: str, target: str,
                         platform: str = sys.platform) -> None:
    """Rename to an unused name atomically; e.g. move_without_replace(fd, "AGENTS.md", ".aside").

    A check by name cannot protect a later unlink by name (MIR-889 P0), so callers move
    the entry aside and judge what they moved. An occupied target raises EEXIST and
    nothing is renamed; unsupported platforms raise ENOTSUP/ENOSYS.
    """
    rename_with_flag(NOREPLACE_CALLS, platform, directory_fd, source, target)


def rename_with_flag(calls: dict[str, tuple[str, int]], platform: str, directory_fd: int,
                     first: str, second: str) -> None:
    """Pick the platform's flagged rename; e.g. rename_with_flag(SWAP_CALLS, "linux", fd, "a", "b")."""
    symbol, flag = calls.get(platform, ("", 0))
    if not symbol:
        raise OSError(errno.ENOTSUP, f"platform={platform!r}; expected one of {sorted(calls)} "
                                     "with an atomic flagged rename call")
    swap_names(symbol, flag, directory_fd, first, second)


def swap_names(symbol: str, flag: int, directory_fd: int, first: str, second: str) -> None:
    """Call the libc flagged rename and surface errno; e.g. EINVAL from a filesystem without it."""
    call = getattr(ctypes.CDLL(None, use_errno=True), symbol, None)
    if call is None:
        raise OSError(errno.ENOSYS, f"libc symbol={symbol!r}; expected an exported flagged rename call")
    call.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    call.restype = ctypes.c_int
    if call(directory_fd, os.fsencode(first), directory_fd, os.fsencode(second), flag) == 0:
        return
    code = ctypes.get_errno()
    raise OSError(code, f"{os.strerror(code)}; names={(first, second)!r}; "
                        f"expected {symbol} flags={flag:#x} to rename them atomically")
