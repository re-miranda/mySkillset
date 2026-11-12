"""Atomic two-name swap: the one rename that displaces an entry instead of destroying it."""
from __future__ import annotations

import ctypes
import errno
import os
import sys
from collections.abc import Callable

# Injected into InstructionFiles; e.g. tests pass a named fault fake with this shape.
ExchangeNames = Callable[[int, str, str], None]

# Both calls share one C signature: (int, const char *, int, const char *, unsigned int).
# Linux RENAME_EXCHANGE and macOS RENAME_SWAP are both 0x2.
SWAP_CALLS: dict[str, tuple[str, int]] = {"linux": ("renameat2", 2), "darwin": ("renameatx_np", 2)}


def exchange(directory_fd: int, first: str, second: str, platform: str = sys.platform) -> None:
    """Swap two names in one directory atomically; e.g. exchange(fd, ".staged", "AGENTS.md").

    Plain rename cannot inspect what it overwrites (MIR-696 P0), so callers swap and
    then judge the displaced entry. Unsupported platforms raise ENOTSUP/ENOSYS.
    """
    symbol, flag = SWAP_CALLS.get(platform, ("", 0))
    if not symbol:
        raise OSError(errno.ENOTSUP, f"platform={platform!r}; expected one of {sorted(SWAP_CALLS)} "
                                     "with an atomic rename-exchange call")
    swap_names(symbol, flag, directory_fd, first, second)


def swap_names(symbol: str, flag: int, directory_fd: int, first: str, second: str) -> None:
    """Call the libc swap and surface errno; e.g. EINVAL from a filesystem without exchange."""
    call = getattr(ctypes.CDLL(None, use_errno=True), symbol, None)
    if call is None:
        raise OSError(errno.ENOSYS, f"libc symbol={symbol!r}; expected an exported rename-exchange call")
    call.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    call.restype = ctypes.c_int
    if call(directory_fd, os.fsencode(first), directory_fd, os.fsencode(second), flag) == 0:
        return
    code = ctypes.get_errno()
    raise OSError(code, f"{os.strerror(code)}; names={(first, second)!r}; "
                        f"expected {symbol} to swap two existing entries")
