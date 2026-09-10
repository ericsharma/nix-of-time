{ config, ... }:

{
  # ── Papra (minimalistic document management and archiving) ───────────────────
  # Data dir: /srv/papra/app-data  (SQLite db + uploaded documents)
  # Port: 1221
  #
  # Papra bundles its own SQLite database, so a single container is the whole
  # stack — no sidecar DB, which is why this is a plain Podman module here
  # rather than a docker-services/ entry. See docs/architecture.md.
  #
  # It lives in gmktec/ and NOT in ../optional/ on purpose. trigkey imports
  # every file under optional/ with listFilesRecursive and those modules carry
  # no enable flag, so a papra.nix there would silently start a second Papra on
  # trigkey — same AUTH_SECRET, same APP_BASE_URL pointing back at gmktec, and
  # its own empty /srv/papra/app-data. Host-specific services belong in the
  # host directory, next to jellyfin.nix and sabnzbd.nix.
  #
  # AUTH_SECRET signs session cookies and must stay stable across restarts, or
  # every user is silently logged out on rebuild. It comes from sops as a full
  # env file so the value never lands in the world-readable Nix store.
  #
  # APP_BASE_URL is the URL browsers reach Papra on. Papra uses it to build
  # absolute links (email confirmations, share URLs) — a mismatch here shows up
  # as broken links, not a hard failure. On gmktec the value is the portless
  # LAN name (declared in inventory.nix under gmktec.portlessAliases); on a host
  # that reverse-proxies Papra publicly, override APP_BASE_URL in the
  # environment file to that URL.

  virtualisation.oci-containers.containers.papra = {
    image = "ghcr.io/papra-hq/papra:latest";
    ports = [ "127.0.0.1:1221:1221" ];
    volumes = [
      "/srv/papra/app-data:/app/app-data"
    ];
    environmentFiles = [
      config.sops.secrets."papra/env".path
    ];
  };

  sops.secrets."papra/env" = { };

  # The papra image runs as `nonroot` (uid/gid 999), NOT root. Without this the
  # container starts and immediately fails migration with
  # `EACCES: permission denied, mkdir './app-data/db'` on the bind mount. The
  # rootful podman on this host does no uid remapping, so uid 999 inside the
  # container is uid 999 on the host and a plain chown is enough. Numeric IDs
  # rather than a NixOS user, because the mapping is defined by the upstream
  # image, not by us — if a future image renumbers it, this is what has to move.
  #
  # `ls -la /srv/papra/app-data` will therefore show `dhcpcd:dhcpcd` on gmktec,
  # because that daemon's system user happens to hold uid 999. It is a name
  # collision, not shared access: the podman container has no view of anything
  # outside /srv/papra/app-data, and dhcpcd has no reason to read that path.
  systemd.tmpfiles.rules = [
    "d /srv/papra 0755 root root -"
    "d /srv/papra/app-data 0750 999 999 -"
  ];
}
