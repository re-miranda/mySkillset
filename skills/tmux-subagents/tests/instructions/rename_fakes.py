"""Named rename fakes for the pre-write rename proof (MIR-891)."""
from __future__ import annotations

import errno
import os


class FlagIgnoringRename:
    """Model a filesystem that accepts a flagged rename but performs a plain one."""

    def __call__(self, directory_fd: int, first: str, second: str) -> None:
        """Rename over the second name.

        Example: no swap happens and an occupied name is replaced.
        """
        os.rename(first, second, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)


class BrokenRename:
    """Model a rename that fails for a reason other than missing support."""

    def __call__(self, directory_fd: int, first: str, second: str) -> None:
        """Fail like a bad disk.

        Example: any pair of names raises EIO and nothing is renamed.
        """
        raise OSError(errno.EIO, f"fixture: rename failed for {(first, second)!r}")
