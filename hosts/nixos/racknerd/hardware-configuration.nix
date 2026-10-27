# The disk as RackNerd's Ubuntu image left it; NixOS was installed in place
# (NIXOS_LUSTRATE), not with nixos-anywhere: its kexec step is OOM-killed on
# 957 MB. vda1 = BIOS boot (GRUB core), vda2 = root, vda3 = swap.
{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub.device = "/dev/vda";

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/14d4bb60-8bf5-4834-b642-bc967d5dabe7";
    fsType = "ext4";
  };

  swapDevices = [ { device = "/dev/disk/by-uuid/8ceeef92-be23-4607-976a-4d6f0908ade4"; } ];
}
