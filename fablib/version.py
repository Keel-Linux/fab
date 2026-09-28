"""The version this package was built as.

Read from the file debian/rules writes into the package, never from apt.
Asking apt was the old answer and it asked the wrong question: "apt-cache
policy fab" reports whatever package is called fab on this machine, which
after the rename to keel-fab is a different package or none, and a host that
installed the .deb from a file has no archive entry to report at all.

bt-layer records this string in every layer manifest as fab_version, so a
wrong answer here is a wrong provenance record on every image built
afterwards. That is why the override below is FAB_VERSION_FILE and not
FAB_SHARE_PATH: FAB_SHARE_PATH is a build variable, and although product.mk
and turnkey.mk both set it with ?= and neither exports it, one exported
FAB_SHARE_PATH pointing at a checkout would be enough to make every manifest
built afterwards record "unknown". Nothing a build environment sets for its
own reasons may redirect this lookup.
"""

import os
from pathlib import Path

VERSION_PATH = "/usr/share/fab/version"
UNKNOWN = "unknown"


def version_file() -> Path:
    """The file the package recorded its version in.

    FAB_VERSION_FILE exists for the tests and for nothing else. No build sets
    it, and nothing in this repository reads it outside this function.
    """
    return Path(os.getenv("FAB_VERSION_FILE") or VERSION_PATH)


def package_version() -> str:
    """The recorded version, or UNKNOWN when there is nothing to read."""
    try:
        recorded = version_file().read_text()
    except OSError:
        return UNKNOWN
    return recorded.strip() or UNKNOWN
