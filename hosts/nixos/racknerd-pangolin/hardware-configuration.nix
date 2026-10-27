# The disk as RackNerd's Ubuntu image left it; NixOS was installed in place
# (NIXOS_LUSTRATE). vda1 = BIOS boot (GRUB core), vda2 = root, vda3 = swap.
# Same image as racknerd, so the root UUID is the same; swap differs.
{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub.device = "/dev/vda";

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/14d4bb60-8bf5-4834-b642-bc967d5dabe7";
    fsType = "ext4";
  };

  swapDevices = [ { device = "/dev/disk/by-uuid/2b043f15-6f15-4a82-8489-f72b018da34c"; } ];
}
