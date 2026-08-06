# Adding a new machine

This procedure installs a new NixOS host from the minimal ISO. `gmktec` was
onboarded with it on 2026-08-06. Replace `<name>` with your host name and
`<ip>` with the machine's LAN address.

## Read this first

`hosts/nixos/common/default.nix` sets the `eric` password from sops with
`neededForUsers = true`. The host must decrypt `secrets/secrets.yaml` at install
time. If it cannot, the install completes but `eric` gets no password, and you
cannot log in.

So you must make the SSH host key **before** you install, not after. Step 2
does this. `nixos-install` keeps an existing host key and does not replace it.

---

## 1. Prepare the target from the live USB

Boot the minimal ISO. Set up the network with `nmtui`.

`nmtui` reports `read-only filesystem` when it writes the host name. Ignore
this error. The live host name has no effect on the installed system.

Give yourself SSH access from the machine that holds the repo:

```bash
# On the target
sudo passwd nixos
ip -4 addr show scope global
```

```bash
# On the repo machine
nix-shell -p sshpass --run "sshpass -p <password> ssh-copy-id nixos@<ip>"
```

## 2. Partition, format, and make the host key

Check the disk first. `lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL` shows every device.

> **Warning:** the disk can hold data. `gmktec` held a Proxmox ZFS pool.
> External drives can also be connected. Confirm the model string before you
> erase anything.

```bash
DISK=/dev/nvme0n1

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

Clear ZFS labels first if the disk held a pool: `sudo zpool labelclear -f ${DISK}p3`.

Now make the host key and read its age key:

```bash
sudo mkdir -p /mnt/etc/ssh
sudo ssh-keygen -t ed25519 -N "" -C <name> -f /mnt/etc/ssh/ssh_host_ed25519_key
sudo chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key

nix-shell -p ssh-to-age --run 'ssh-to-age < /mnt/etc/ssh/ssh_host_ed25519_key.pub'
```

Keep the age key. Step 4 needs it.

Get the hardware config:

```bash
sudo nixos-generate-config --root /mnt --show-hardware-config
```

## 3. Write the host directory

Create `hosts/nixos/<name>/hardware-configuration.nix` from the output of
step 2. Then create `hosts/nixos/<name>/default.nix`:

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

> **Do not copy trigkey's import block.** `hosts/nixos/trigkey/default.nix` pulls
> in every file under `hosts/nixos/optional/` with `listFilesRecursive`. Those
> modules carry no enable flags. Each one starts its service without a
> condition, and many need trigkey's hardware. List the modules you want.

`../common` authorises the `eric@ericsharma.xyz` workstation key only. Add
other keys per host:

```nix
users.users.eric.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... trigkey" ];
```

## 4. Wire the host into the flake

1. **`.sops.yaml`** — add the age key from step 2 as an anchor. Add the anchor
   to the `secrets/secrets.yaml` key group. See [secrets.md](secrets.md#adding-a-new-sops-recipient).
2. Re-encrypt: `nix develop -c sops updatekeys secrets/secrets.yaml`
3. **`flake.nix`** — add a `nixosConfigurations.<name>` entry. Copy the
   `gmktec` block. Pass only the `specialArgs` your imports need. Add the host
   to `checks.${system}` too.
4. **`home/<name>/default.nix`** — import `../common`.
5. **`inventory.nix`** — add `<name> = { address = "<ip>"; };`. Prometheus turns
   every inventory host into a scrape target. Reserve the address in your router.
6. **`git add`** the new files. A flake in a git tree ignores untracked files,
   so evaluation fails without this step.

Verify before you install:

```bash
nix build --no-link --print-out-paths .#nixosConfigurations.<name>.config.system.build.toplevel
```

## 5. Install

Build on the repo machine, then push the closure. This installs the exact
system you verified:

```bash
CLOSURE=$(nix build --no-link --print-out-paths .#nixosConfigurations.<name>.config.system.build.toplevel)
nix copy --to ssh://nixos@<ip> --no-check-sigs $CLOSURE
ssh nixos@<ip> "sudo nixos-install --root /mnt --system $CLOSURE --no-root-passwd --no-channel-copy"
```

The log must contain this line:

```
sops-install-secrets: Imported /etc/ssh/ssh_host_ed25519_key as age key with fingerprint age1...
```

That line proves the host decrypts your secrets. The `eric` password works.
If the line is absent, stop. Do not reboot. Repeat step 4.

## 6. First boot

**Remove the USB device before you reboot.** The firmware starts the USB device
again if you leave it in. The live ISO makes a new SSH host key at each boot, so
you see a host key mismatch and lose your `authorized_keys` file.

```bash
ssh nixos@<ip> 'sudo umount -R /mnt; sudo systemctl reboot'
ssh-keygen -R <ip>
```

If the machine does not start from the SSD, press `F7` for a one-time boot menu
or `Del` for the firmware setup. Set `Linux Boot Manager` first in the boot
order. Disable Secure Boot and CSM.

Verify the host key. It must match the key from step 2:

```bash
ssh-keyscan -t ed25519 <ip> | ssh-keygen -lf -
```

## 7. Finish

Copy the repo to the host, then rebuild:

```bash
tar czf - --exclude=result --exclude=graphify-out --exclude=.direnv --exclude=.claude . \
  | ssh eric@<ip> 'mkdir -p ~/nixos-config && tar xzf - -C ~/nixos-config'
ssh eric@<ip> 'cd ~/nixos-config && sudo nixos-rebuild switch --flake .#<name>'
```

`programs.nh.flake` points at `/home/eric/nixos-config`, so `rebuild` works on
the host after this step.

Later changes deploy from trigkey without a copy:

```bash
nixos-rebuild switch --flake .#<name> --target-host eric@<ip> --sudo
```

Rebuild trigkey last. This applies the `inventory.nix` change and starts the
new scrape targets:

```bash
rebuild
```

## Checks

```bash
ssh eric@<ip> 'systemctl is-system-running; systemctl --failed'
ssh eric@<ip> 'sudo ls /run/secrets-for-users/'   # sops decryption works
curl -s 'http://127.0.0.1:9090/api/v1/targets?state=active' | grep <name>
```

## macOS

macOS machines go under `hosts/darwin/` through nix-darwin. That directory is
scaffolding only.
