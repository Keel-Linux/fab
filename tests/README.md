
## Note on the SOURCE_DATE_EPOCH measurement

The commit "Honour SOURCE_DATE_EPOCH when set" quotes squashfs and ISO hashes
from 2026-09-22. That run packed an empty root.patched (the deck was
unmounted), so those hashes are of an empty image. The change was re-measured
on 2026-09-26 on a real core tree with fab 1.1.1+keel1: two packings gave
squashfs 47ed341d65f0f93bae6a304cabad839035d85b1f662616db63ca4f6fb8942801
(385,662,976 bytes) and ISO
ab615ac60ac19148a56adbc3506ac53da6733bda2760d759588c552263e6b22b
(442,499,072 bytes). Always check `mountpoint build/root.patched` before
packing and record sizes next to hashes.
