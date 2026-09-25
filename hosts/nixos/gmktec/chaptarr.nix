{
  config,
  pkgs,
  ...
}:

let
  port = 8789;
  uid = 8789;
  servarrApi = import ./servarr-api.nix { inherit pkgs; };

  # The NFS export of trigkey's Kavita book folder. See
  # ../trigkey/kavita-nfs.nix for the server side.
  kavitaMount = "/mnt/kavita";

  reconcile = pkgs.writeShellScript "chaptarr-reconcile" ''
    set -euo pipefail

    PATH=${
      pkgs.lib.makeBinPath [
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
      ]
    }

    # Chaptarr is a Readarr fork, so it speaks /api/v1, not Sonarr's v3.
    api_url="http://127.0.0.1:${toString port}/api/v1"
    key="$CHAPTARR__AUTH__APIKEY"
    . ${servarrApi}

    wait_ready

    # ── Root folder ──────────────────────────────────────────────────────────
    # ensure_root_folder does not fit here: Chaptarr rejects a root folder
    # without a folderType (0 mixed, 1 audiobook, 2 ebook) and the per-type
    # default profiles. Look the profiles up by name, because their IDs are
    # assigned on first start.
    if api GET /rootfolder | jq -e 'any(.[]; .path == "/ebooks")' >/dev/null; then
      echo "root folder /ebooks already present"
    else
      quality="$(api GET /qualityprofile | jq -e 'map(select(.name == "E-Book")) | .[0].id')"
      metadata="$(api GET /metadataprofile | jq -e 'map(select(.name == "Ebook Default")) | .[0].id')"
      api POST /rootfolder -d "$(
        jq -n --argjson q "$quality" --argjson m "$metadata" '{
          name: "Kavita",
          path: "/ebooks",
          folderType: 2,
          defaultTags: [],
          isCalibreLibrary: false,
          ebookQualityProfileId: $q,
          ebookMetadataProfileId: $m,
          ebookTags: []
        }'
      )" >/dev/null
      echo "added root folder /ebooks"
    fi

    # ── SABnzbd download client ──────────────────────────────────────────────
    # Chaptarr has separate ebook, audiobook and music category fields.
    # sabnzbd_payload sets all of them to "books", the [[books]] category in
    # sabnzbd.ini, so finished downloads land in /data/usenet/complete/books.
    sab="$(
      api GET /downloadclient/schema \
        | jq -e 'map(select(.implementation == "Sabnzbd")) | .[0] // empty'
    )" || { echo "no Sabnzbd entry in Chaptarr's download client schema" >&2; exit 1; }
    upsert downloadclient SABnzbd "$(sabnzbd_payload "$(cat ${
      config.sops.secrets."sabnzbd/api-key".path
    })" books <<<"$sab")"
  '';
in
{
  # ── Chaptarr (ebook management, Readarr fork) ────────────────────────────────
  # Port: 8789 (LAN only, see the nftables rule below)
  # Config: this module. config.xml comes from CHAPTARR__* env vars; the root
  #   folder and the SABnzbd download client are reconciled through the REST
  #   API by chaptarr-reconcile.service, and prowlarr-reconcile.service adds
  #   the Prowlarr app link.
  # Data: /srv/chaptarr/config (SQLite). The library is NOT on this machine:
  #   the root folder /ebooks is an NFS mount of trigkey's
  #   /srv/kavita/books/books/chaptarr, so every import goes straight into
  #   Kavita's "Books" library.
  # NOT backed up here — the database holds only the author list and history,
  #   both rebuilt from the library and the indexer. The books themselves are
  #   backed up on trigkey with the rest of /srv/kavita.
  #
  # This is the one exception to the single-filesystem rule in
  # ./media-storage.nix. An import from /data/usenet to the NFS mount is a copy,
  # not a hardlink. That is acceptable for ebooks, which are a few MB each.
  #
  # A container, not a native module: nixpkgs has no Chaptarr package. It uses
  # the host network, not a published port, for two reasons. It must reach
  # SABnzbd and Prowlarr on 127.0.0.1, and a podman-published port bypasses the
  # nftables input chain, so the LAN-only rule below would not apply to it.
  #
  # Images: `latest` stays at 0.9.911 (2026-08-08) while versioned tags
  # continue. Pin a version and bump it by hand.

  # restartUnits: a changed key must reach the running app and be pushed back
  # through the reconcile, or the stored objects keep the old value.
  sops.secrets."chaptarr/env".restartUnits = [
    "podman-chaptarr.service"
    "chaptarr-reconcile.service"
    # Prowlarr stores this key in its app link, so that must be rewritten too.
    "prowlarr-reconcile.service"
  ];

  # A real account for the container's PUID, so `ls` shows a name and the
  # number cannot be reused by accident. `media` as the PRIMARY group, for the
  # reason given in ./sabnzbd.nix.
  users.users.chaptarr = {
    isSystemUser = true;
    inherit uid;
    group = "media";
  };

  virtualisation.oci-containers.containers.chaptarr = {
    image = "docker.io/chaptarr/chaptarr:0.9.958";
    extraOptions = [ "--network=host" ];
    volumes = [
      "/srv/chaptarr/config:/config"
      # Same absolute path as SABnzbd uses, so no remote path mapping is needed.
      "/data/usenet:/data/usenet"
      "${kavitaMount}:/ebooks"
    ];
    environmentFiles = [ config.sops.secrets."chaptarr/env".path ];
    environment = {
      TZ = "America/New_York";
      PUID = toString uid;
      PGID = toString config.users.groups.media.gid;
      UMASK = "002";
      CHAPTARR__SERVER__PORT = toString port;
      # Same posture as Sonarr: RFC1918 clients — all the firewall admits —
      # skip the login entirely, so no account is ever created.
      CHAPTARR__AUTH__METHOD = "Forms";
      CHAPTARR__AUTH__REQUIRED = "DisabledForLocalAddresses";
      # No CHAPTARR__UPDATE__MECHANISM: 0.9.958 ignores it ("docker" and
      # "external" both leave builtIn). Automatic install is off by default,
      # and the pinned image above is the real update control.
    };
  };

  systemd.services.podman-chaptarr = {
    after = [ "sops-nix.service" ];
    # Requires the NFS mount, so the container does not start against the
    # empty mount point when trigkey is down.
    unitConfig.RequiresMountsFor = [
      "/data"
      kavitaMount
    ];
  };

  systemd.services.chaptarr-reconcile = {
    description = "Reconcile Chaptarr root folder and download client";
    after = [
      "podman-chaptarr.service"
      "sabnzbd.service"
    ];
    requires = [ "podman-chaptarr.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ reconcile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = config.sops.secrets."chaptarr/env".path;
      ExecStart = reconcile;
      # Runs as root only to read the SABnzbd API key; it touches nothing else.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
    };
  };

  # ── NFS client ───────────────────────────────────────────────────────────────
  # NFSv4.2 only, which needs no rpcbind or statd. `soft` makes an I/O error
  # instead of a hung process when trigkey is down; Chaptarr then marks the
  # import as failed and tries again. `nofail` keeps a trigkey outage from
  # blocking boot here. If trigkey was down at boot, start the mount by hand:
  #   sudo systemctl start mnt-kavita.mount podman-chaptarr.service
  boot.supportedFilesystems.nfs = true;

  fileSystems.${kavitaMount} = {
    device = "192.168.0.202:/srv/kavita/books/books/chaptarr";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "_netdev"
      "nofail"
      "soft"
      "timeo=150"
      "retrans=3"
      "x-systemd.mount-timeout=30s"
    ];
  };

  # /data/usenet/complete/books is the SABnzbd category folder. SABnzbd
  # makes it on the first download; until then Chaptarr's health check
  # reports that it cannot see it. Create it now, owned like its siblings.
  systemd.tmpfiles.rules = [
    "d /data/usenet/complete/books 2775 sabnzbd media -"
    "d /srv/chaptarr 0755 root root -"
    "d /srv/chaptarr/config 0750 chaptarr media -"
  ];

  # LAN subnet only. Chaptarr asks for no login from a local address, so
  # whoever reaches this port controls the library.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport ${toString port} accept comment "chaptarr web UI from LAN"
  '';
}
