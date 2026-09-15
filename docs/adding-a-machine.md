# Adding a machine

Install a new NixOS host from the minimal ISO, with sops working on first boot. `gmktec` was built this way on 2026-08-06.

Replace `<name>` and `<ip>` throughout.

> **Make the SSH host key before `nixos-install`.** The `eric` password comes from sops (`neededForUsers = true`). If the host can't decrypt at install time, the install still succeeds, but `eric` has no password and you can't log in. Step 2 handles this.

## 1. Get SSH into the live USB

On the target, boot the ISO and connect with `nmtui`. Ignore its `read-only filesystem` error about the host name. Then:

```bash
sudo passwd nixos
ip -4 addr show scope global
```

On the repo machine:

```bash
nix-shell -p sshpass --run "sshpass -p <password> ssh-copy-id nixos@<ip>"
```

## 2. Partition, format, make the host key

> **Warning:** this erases the disk. Run `lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL` and confirm the model string first. External drives may be attached, and gmktec's disk held a Proxmox ZFS pool.

```bash
DISK=/dev/nvme0n1
# sudo zpool labelclear -f ${DISK}p3   # only if the disk held a ZFS pool

sudo wipefs -a $DISK
sudo sgdisk --zap-all $DISK

sudo parted $DISK -- mklabel gpt
sudo parted $DISK -- mkpart ESP fat32 1MiB 1GiB
sudo parted $DISK -- set 1 esp on
sudo parted $DISK -- mkpart root ext4 1GiB 100%
sudo mkfs.fat -F32 -n boot ${DISK}p1
sudo mkfs.ext4 -L nixos -F ${DISK}p2

sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount -o umask=077 /dev/disk/by-label/boot /mnt/boot
```

Make the host key, then save the two outputs:

```bash
sudo mkdir -p /mnt/etc/ssh
sudo ssh-keygen -t ed25519 -N "" -C <name> -f /mnt/etc/ssh/ssh_host_ed25519_key
sudo chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key

nix-shell -p ssh-to-age --run 'ssh-to-age < /mnt/etc/ssh/ssh_host_ed25519_key.pub'   # age key, for step 4
sudo nixos-generate-config --root /mnt --show-hardware-config                        # for step 3
```

`nixos-install` keeps an existing host key.

## 3. Write `hosts/nixos/<name>/`

1. `hardware-configuration.nix`: the output from step 2.
2. `default.nix`:

```nix
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../common
    ../optional/monitoring/exporters.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "<name>";
  networking.useDHCP = false;
  networking.interfaces.enp1s0.useDHCP = true;

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  security.sudo.wheelNeedsPassword = false;

  # nixos-rebuild --target-host pushes an unsigned closure. The daemon refuses
  # it unless the SSH user is trusted.
  nix.settings.trusted-users = [ "root" "eric" ];

  system.stateVersion = "25.11";
}
```

- **Never copy trigkey's import block.** It globs all of `optional/`, and those modules start unconditionally. List the modules you want.
- `../common` authorises only the `eric@ericsharma.xyz` workstation key. Add others per host:

```nix
users.users.eric.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... trigkey" ];
```

## 4. Wire the host into the flake

1. **`.sops.yaml`:** add the age key from step 2 as an anchor, and add the anchor to the `secrets/secrets.yaml` key group. Then re-encrypt: `nix develop -c sops updatekeys secrets/secrets.yaml`
2. **`flake.nix`:** copy the `gmktec` block under `nixosConfigurations`, pass only the `specialArgs` your imports need, and add the host to `checks.${system}`.
3. **`home/<name>/default.nix`:** import `../common`.
4. **`inventory.nix`:** add `<name> = { address = "<ip>"; portlessAliases = { }; };` and reserve the address in the router. Prometheus scrapes every inventory host.
5. **`git add`** the new files. The flake ignores untracked files.

Check it builds:

```bash
nix build --no-link --print-out-paths .#nixosConfigurations.<name>.config.system.build.toplevel
```

## 5. Install

Build on the repo machine and push the exact closure you checked:

```bash
CLOSURE=$(nix build --no-link --print-out-paths .#nixosConfigurations.<name>.config.system.build.toplevel)
nix copy --to ssh://nixos@<ip> --no-check-sigs $CLOSURE
ssh nixos@<ip> "sudo nixos-install --root /mnt --system $CLOSURE --no-root-passwd --no-channel-copy"
```

The log must contain:

```
sops-install-secrets: Imported /etc/ssh/ssh_host_ed25519_key as age key with fingerprint age1...
```

No line? Stop. Do not reboot. Redo step 4.

## 6. First boot

1. **Remove the USB stick.** If it boots the ISO again, you get a new host key, a key mismatch, and no `authorized_keys`.
2. Reboot and forget the old key:
   ```bash
   ssh nixos@<ip> 'sudo umount -R /mnt; sudo systemctl reboot'
   ssh-keygen -R <ip>
   ```
3. Doesn't boot from the SSD? `F7` opens the boot menu, `Del` the firmware setup. Put `Linux Boot Manager` first, and disable Secure Boot and CSM.
4. Confirm the host key matches step 2: `ssh-keyscan -t ed25519 <ip> | ssh-keygen -lf -`

## 7. First rebuild

Copy the repo over and rebuild on the host:

```bash
tar czf - --exclude=result --exclude=graphify-out --exclude=.direnv --exclude=.claude . \
  | ssh eric@<ip> 'mkdir -p ~/nixos-config && tar xzf - -C ~/nixos-config'
ssh eric@<ip> 'cd ~/nixos-config && sudo nixos-rebuild switch --flake .#<name>'
```

After this, `rebuild` works on the host (`programs.nh.flake` points at `~/nixos-config`). Later deploys from trigkey need no copy:

```bash
nixos-rebuild switch --flake .#<name> --target-host eric@<ip> --sudo
```

Run `rebuild` on trigkey last. That applies the `inventory.nix` change and adds the scrape targets.

## Check

```bash
ssh eric@<ip> 'systemctl is-system-running; systemctl --failed'
ssh eric@<ip> 'sudo ls /run/secrets-for-users/'   # sops decryption works
curl -s 'http://127.0.0.1:9090/api/v1/targets?state=active' | grep <name>   # on trigkey
```

## macOS

macOS hosts go in `hosts/darwin/` through nix-darwin. `m1-mini` is wired in as `darwinConfigurations.m1-mini`. `hosts/darwin/m1-air/` is empty.
