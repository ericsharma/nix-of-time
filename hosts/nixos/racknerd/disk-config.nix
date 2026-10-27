# disko layout for the RackNerd KVM: one 20 GB virtio disk, BIOS boot (no
# EFI firmware on this plan), so GRUB needs the 1 MiB EF02 partition.
# nixos-anywhere ERASES /dev/vda with this layout on install.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        # 1 GB RAM: Pangolin's Node process alone is ~300 MB. zram absorbs
        # short spikes; this partition is the floor against the OOM killer.
        swap = {
          size = "1G";
          content.type = "swap";
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
