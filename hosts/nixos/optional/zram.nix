{ ... }:

# Compressed swap in RAM, tuned for zram rather than for a disk.
# Not in ../common: the RackNerd nodes also have a disk swap partition, and
# page-cluster = 0 / swappiness = 180 assume zram is the only swap.
# Source: https://lowendspirit.com/discussion/11543
{
  # No swap partition on trigkey or gmktec. zram absorbs the rare spike
  # (Immich ML, a large build) instead of the OOM killer.
  zramSwap.enable = true;

  boot.kernel.sysctl = {
    # zram swap-in is a decompress, not a disk seek. Prefer to compress cold
    # anonymous pages over dropping page cache.
    "vm.swappiness" = 180;
    # Default 3 reads 8 pages ahead on each swap-in. That is wasted work on zram.
    "vm.page-cluster" = 0;
    # Start kswapd earlier, so allocations do not stall in direct reclaim.
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };
}
