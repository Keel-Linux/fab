"""The version this package was built as.

Read from the file debian/rules writes into the package, never from apt.
Asking apt was the old answer and it asked the wrong question: "apt-cache
policy fab" reports whatever package is called fab on this machine, which
after the rename to keel-fab is a different package or none, and a host that
installed the .deb from a file has no archive entry to report at all.

bt-layer records this string in every layer manifest as fab_version, so a
wrong answer here is a wrong provenance record on every image built
afterwards.
"""

import os
from pathlib import Path

DEFAULT_SHARE_PATH = "/usr/share/fab"
VERSION_FILE = "version"
UNKNOWN = "unknown"


def share_path() -> Path:
    """Where the package put its data, overridable for tests."""
    return Path(os.getenv("FAB_SHARE_PATH") or DEFAULT_SHARE_PATH)


def package_version() -> str:
    """The recorded version, or UNKNOWN when there is nothing to read."""
    try:
        recorded = (share_path() / VERSION_FILE).read_text()
    except OSError:
        return UNKNOWN
    return recorded.strip() or UNKNOWN
