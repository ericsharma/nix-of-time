{
  config,
  lib,
  pkgs,
  eternatv,
  ...
}:

let
  # ── Tunables ───────────────────────────────────────────────────────────────
  #
  # `channels` is the list of named per-collection sub-streams. Each emits its
  # own HLS manifest at /<name>/stream.m3u8 and walks its `collections` in
  # deterministic order, looping when exhausted (no seen-history).
  #
  # A `main` channel is auto-derived as the union of every collection across
  # every entry below. main uses the random + seen-history picker (so 500
  # items don't repeat too eagerly), and is the only channel that accepts user
  # submissions via the /enqueue API.
  #
  # Useful additional collections (uncomment a few or add new channels):
  #   "free-to-use"          # rights-cleared media
  #   "audio-video"          # generic A/V landing
  #   "collections/national-screening-room"
  #   "collections/early-motion-pictures-1897-to-1920"
  #   "collections/inventing-entertainment-the-motion-pictures-and-sound-recordings-of-the-edison-companies"
  channels = [
    {
      name = "animation";
      collections = [ "collections/origins-of-american-animation" ];
    }
    {
      name = "vintage-nyc";
      collections = [ "collections/early-films-of-new-york-1898-to-1906" ];
    }
  ];

  mainChannelName = "main";
  mainChannel = {
    name = mainChannelName;
    collections = lib.unique (lib.concatMap (c: c.collections) channels);
  };
  allChannels = [ mainChannel ] ++ channels;

  # ── Audio sources ─────────────────────────────────────────────────────────
  # Each entry is one selectable radio stream the *browser* plays alongside the
  # silent HLS video. Two URLs per source because the orchestrator's archive
  # baker runs on this host (so loopback is fine + free) while the player runs
  # in the browser (so it needs a publicly reachable URL).
  #
  # `kind` controls how /api/now resolves "what's playing":
  #   - "icecast": curl /status-json.xsl on serverUrl (loopback)
  #   - "nts":    curl https://www.nts.live/api/v2/live and pick by `ntsChannel`
  audioSources = [
    {
      id = "icecast";
      label = "trigkey radio";
      publicUrl = "https://radio.ericsharma.xyz/stream";
      serverUrl = "http://127.0.0.1:8000/stream";
      kind = "icecast";
    }
    {
      id = "nts1";
      label = "NTS 1";
      publicUrl = "https://audio-edge-vqwx4.yyz.g.radiomast.io/nts1";
      serverUrl = "https://audio-edge-vqwx4.yyz.g.radiomast.io/nts1";
      kind = "nts";
      ntsChannel = "1";
    }
    {
      id = "nts2";
      label = "NTS 2";
      publicUrl = "https://audio-edge-vqwx4.yyz.g.radiomast.io/nts2";
      serverUrl = "https://audio-edge-vqwx4.yyz.g.radiomast.io/nts2";
      kind = "nts";
      ntsChannel = "2";
    }
  ];
  defaultAudio = "nts2";

  hlsListenPort = 8088;
  apiListenPort = 8089; # enqueue API, 127.0.0.1 only — expose via Pangolin if remote
  cacheTarget = 3; # how many normalised mp4s to keep ready PER channel

  stateDir = "/var/lib/radio-video";
  cacheRoot = "${stateDir}/cache"; # per-channel subdirs: cache/<ch>/*.mp4
  priorityDir = "${stateDir}/priority"; # main-only, user-submitted clips, FIFO
  hlsRoot = "${stateDir}/hls"; # per-channel subdirs: hls/<ch>/stream.m3u8
  capturesDir = "${stateDir}/captures"; # user "instant replay" clips, kept 7d
  userClipsDir = "${stateDir}/user-clips"; # archived user submissions, kept 7d
  fillerPath = "${stateDir}/filler.mp4";
  runtimeDir = "/run/radio-video";
  # Rolling per-source audio buffer for /api/capture. Tmpfs-backed so it
  # vanishes on restart and never touches disk. Sized to cover the longest
  # allowed capture window (captureMaxSeconds) plus a safety margin.
  audioBufferDir = "${runtimeDir}/audio-buf";
  audioSegSeconds = 2;
  audioSegWrap = 130; # 130 × 2s = 260s (> captureMaxSeconds=240)

  # How many recent HLS segments to keep on disk per channel. Each segment is
  # ~4s, so 60 ≈ 4 minutes of instant-replay lookback. Bumping this widens the
  # window users can /capture from at the cost of a bit more disk per channel.
  hlsListSize = 60;
  captureMaxSeconds = 240;

  # ── Garage object store: user captures live in a bucket, not on disk ──────
  # `capturesDir` is the FUSE mountpoint for the bucket below — no captures
  # are stored on the local SSD. rclone keeps a bounded local *cache* of
  # recently-touched objects under `captureCacheDir`; that cache is
  # self-evicting (max-size + max-age below), so disk usage is capped and
  # the bucket remains the single source of truth.
  #
  # The mount uses `--allow-other` so nginx can read it; that needs
  # `programs.fuse.userAllowOther`, which we set unconditionally below so
  # this module is self-sufficient on any host that picks it up.
  captureBucket = "radio-video-captures";
  captureS3Endpoint = "http://127.0.0.1:3900";
  captureS3Region = "garage"; # matches services.garage.settings.s3_api.s3_region
  captureCacheDir = "/var/cache/rclone-radio-video-captures";
  captureRetention = "7d"; # objects older than this are pruned by the timer below

  # Shared rclone env so the mount unit and the prune unit configure the same
  # `captures:` remote without drifting.
  captureRcloneEnv = {
    RCLONE_CONFIG_CAPTURES_TYPE = "s3";
    RCLONE_CONFIG_CAPTURES_PROVIDER = "Other";
    RCLONE_CONFIG_CAPTURES_ENDPOINT = captureS3Endpoint;
    RCLONE_CONFIG_CAPTURES_REGION = captureS3Region;
    RCLONE_CONFIG_CAPTURES_FORCE_PATH_STYLE = "true";
    RCLONE_CONFIG_CAPTURES_ENV_AUTH = "true";
  };

  # ── Package handoff ────────────────────────────────────────────────────────
  # Orchestrator + player live in the ericsharma/eternatv flake. We pass every
  # tunable above into orchestrator.py via a JSON config file; the orchestrator
  # reads it once at startup and uses the values as module-level constants.
  eternatvPkg = eternatv.packages.${pkgs.system}.eternatv;
  eternatvPlayer = eternatv.packages.${pkgs.system}.eternatv-player;

  eternatvConfig = pkgs.writeText "eternatv-config.json" (
    builtins.toJSON {
      inherit
        cacheRoot
        priorityDir
        hlsRoot
        capturesDir
        userClipsDir
        stateDir
        runtimeDir
        audioBufferDir
        fillerPath
        defaultAudio
        cacheTarget
        hlsListSize
        captureMaxSeconds
        audioSegSeconds
        audioSegWrap
        audioSources
        ;
      apiPort = apiListenPort;
      mainName = mainChannelName;
      channels = allChannels;
      playerHtml = "${eternatvPlayer}/index.html";
    }
  );
in
{
  # ── Users ─────────────────────────────────────────────────────────────────
  users.users.radio-video = {
    isSystemUser = true;
    group = "radio-video";
    home = stateDir;
    createHome = false;
  };
  users.groups.radio-video = { };

  # nginx needs to read the HLS directory written by radio-video
  users.users.nginx.extraGroups = [ "radio-video" ];

  # The captures FUSE mount needs `--allow-other` so nginx can serve from
  # it; NixOS gates that behind this option. Set here (idempotent) so this
  # module works standalone, not just when radio.nix happens to be imported.
  programs.fuse.userAllowOther = true;

  # ── Secrets ───────────────────────────────────────────────────────────────
  # rclone S3 credentials for the captures bucket, in env-file form. Keys:
  #   radio-video/rclone-env:
  #     AWS_ACCESS_KEY_ID=...
  #     AWS_SECRET_ACCESS_KEY=...
  # Generate with `garage key create radio-video-captures-rw` then
  # `garage bucket allow radio-video-captures --read --write --key ...`.
  sops.secrets."radio-video/rclone-env" = {
    owner = "radio-video";
  };

  # ── State dirs ────────────────────────────────────────────────────────────
  # `capturesDir` is a FUSE mountpoint for the garage bucket — keep the
  # tmpfiles entry so the empty dir exists for rclone to mount on, but no
  # age field (rclone+the prune timer below own retention now). `userClipsDir`
  # stays local-disk + 7d cleanup (different lifecycle, see scope decision).
  systemd.tmpfiles.rules = [
    "d ${stateDir}      0755 radio-video radio-video -"
    "d ${cacheRoot}     0755 radio-video radio-video -"
    "d ${priorityDir}   0755 radio-video radio-video -"
    "d ${hlsRoot}       0755 radio-video radio-video -"
    "d ${capturesDir}   0755 radio-video radio-video -"
    "d ${userClipsDir}  0755 radio-video radio-video 7d"
    "d ${stateDir}/raw  0755 radio-video radio-video -"
    "d ${runtimeDir}    0755 radio-video radio-video -"
  ]
  ++ lib.concatMap (ch: [
    "d ${cacheRoot}/${ch.name}  0755 radio-video radio-video -"
    "d ${hlsRoot}/${ch.name}    0755 radio-video radio-video -"
  ]) allChannels;

  # ── rclone FUSE mount: garage bucket → ${capturesDir} ─────────────────────
  # Writable mount; orchestrator's `capture_channel` writes mp4s straight
  # to the mountpoint and nginx serves /captures/ from it. The vfs cache is
  # bounded (1G / 1h) and lives under captureCacheDir — bucket is the only
  # place captures actually persist. Retention is handled by the
  # `radio-video-captures-prune` timer below, NOT by tmpfiles or by the
  # cache (cache eviction doesn't delete bucket objects).
  systemd.services.rclone-radio-video-captures = {
    description = "rclone FUSE mount of garage bucket '${captureBucket}' for radio-video captures";
    after = [
      "network-online.target"
      "garage.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "garage.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = captureRcloneEnv;

    # rclone mount shells out to fusermount3; --allow-other only works when
    # it finds the setuid wrapper in /run/wrappers/bin (see radio.nix for
    # the same note — same reason here).
    path = [ "/run/wrappers" ];

    serviceConfig = {
      Type = "notify";
      User = "radio-video";
      Group = "radio-video";
      EnvironmentFile = config.sops.secrets."radio-video/rclone-env".path;
      CacheDirectory = "rclone-radio-video-captures";
      CacheDirectoryMode = "0750";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.rclone}/bin/rclone mount"
        "captures:${captureBucket}"
        capturesDir
        "--allow-other"
        "--vfs-cache-mode full"
        "--vfs-cache-max-size 1G"
        "--vfs-cache-max-age 1h"
        # Flush new captures to garage promptly so nginx serves the
        # canonical object, not a still-uploading cache entry.
        "--vfs-write-back 5s"
        # Listings (orchestrator's list_captures + the UI poll) must see
        # newly-uploaded objects quickly without re-listing the bucket on
        # every request.
        "--dir-cache-time 30s"
        "--cache-dir ${captureCacheDir}"
      ];
      ExecStop = "/run/wrappers/bin/fusermount3 -u ${capturesDir}";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # ── Bucket-side retention ─────────────────────────────────────────────────
  # Daily prune of captures older than ${captureRetention}. Talks to garage
  # directly via the S3 API (no FUSE involved) so it works even if the
  # mount unit is down, and so the cache eviction policy is fully
  # decoupled from the retention policy.
  systemd.services.radio-video-captures-prune = {
    description = "Prune radio-video captures older than ${captureRetention} from garage bucket";
    after = [ "garage.service" ];
    wants = [ "garage.service" ];

    environment = captureRcloneEnv;

    serviceConfig = {
      Type = "oneshot";
      User = "radio-video";
      Group = "radio-video";
      EnvironmentFile = config.sops.secrets."radio-video/rclone-env".path;
      ExecStart = "${pkgs.rclone}/bin/rclone delete --min-age ${captureRetention} captures:${captureBucket}";
    };
  };

  systemd.timers.radio-video-captures-prune = {
    description = "Daily prune of radio-video captures bucket";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # ── Orchestrator service ──────────────────────────────────────────────────
  systemd.services.radio-video-orchestrator = {
    description = "LoC video downloader + ffmpeg HLS supervisor (radio.ericsharma.xyz video sidecar)";
    after = [
      "network-online.target"
      "icecast.service"
      # Must run AFTER the captures bucket is mounted — otherwise the
      # orchestrator would write to the empty underlying dir and those
      # files would be shadowed (or lost) once rclone mounts on top.
      "rclone-radio-video-captures.service"
    ];
    # icecast is only ONE of the audio sources users can pick (the others are
    # NTS streams reachable directly from the browser), and the HLS master
    # no longer mixes audio at all — so a brief icecast outage is no longer
    # a reason to refuse to start. Keep `after` for ordering when both run.
    # The captures mount, by contrast, IS a hard dependency: capture writes
    # must go to garage, not to a shadowed local dir.
    wants = [
      "network-online.target"
      "icecast.service"
    ];
    requires = [ "rclone-radio-video-captures.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "notify";
      NotifyAccess = "main";
      User = "radio-video";
      Group = "radio-video";
      # ffmpeg/curl/coreutils are baked into the wrapper via makeWrapper in
      # the eternatv flake, so no `path = [ ... ]` needed on this unit.
      ExecStart = "${eternatvPkg}/bin/eternatv --config ${eternatvConfig}";
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStartSec = "120s";

      RuntimeDirectory = "radio-video";
      RuntimeDirectoryMode = "0755";
      StateDirectory = "radio-video";
      StateDirectoryMode = "0755";

      # Reasonable hardening (matches the spirit of the rest of the repo)
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [
        stateDir
        runtimeDir
      ];
    };
  };

  # ── nginx: serve HLS on 127.0.0.1:8088 ─────────────────────────────────────
  services.nginx = {
    enable = true;
    virtualHosts."radio-video-hls" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = hlsListenPort;
        }
      ];
      root = hlsRoot;
      # Proxy /api/* to the orchestrator's JSON API on the loopback so the
      # player page can hit /api/channels, /api/queue, POST /api/enqueue
      # same-origin (no CORS, works behind a single Pangolin route).
      locations."/api/" = {
        proxyPass = "http://127.0.0.1:${toString apiListenPort}/";
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_buffering off;
        '';
      };
      # User-captured instant-replay clips. Lives outside hlsRoot so HLS
      # cache-control doesn't apply — these are immutable files and benefit
      # from being downloadable + cacheable.
      locations."/captures/" = {
        alias = "${capturesDir}/";
        extraConfig = ''
          add_header Cache-Control "public, max-age=31536000, immutable" always;
          add_header Access-Control-Allow-Origin * always;
          types { video/mp4 mp4; }
          default_type video/mp4;
        '';
      };
      # Archived user submissions. Same shape as captures.
      locations."/user-clips/" = {
        alias = "${userClipsDir}/";
        extraConfig = ''
          add_header Cache-Control "public, max-age=31536000, immutable" always;
          add_header Access-Control-Allow-Origin * always;
          types { video/mp4 mp4; application/json json; }
          default_type video/mp4;
        '';
      };
      extraConfig = ''
        add_header Cache-Control no-cache always;
        add_header Access-Control-Allow-Origin * always;
        # A `types { ... }` block at server scope REPLACES the inherited
        # http-level map entirely (verified against nginx's behaviour), so we
        # must re-declare every type the player page touches — not just the
        # HLS ones. Skipping text/html here causes the index.html to be served
        # as application/octet-stream, which browsers either download or
        # render as blank.
        types {
          text/html                     html htm;
          application/vnd.apple.mpegurl m3u8;
          video/mp2t                    ts;
        }
        default_type application/octet-stream;
      '';
    };
  };

  # ── Post-deploy one-time setup (manual) ───────────────────────────────────
  #
  # 0. Provision the captures bucket on garage (one-time, before first deploy):
  #      sudo garage bucket create ${captureBucket}
  #      sudo garage key create radio-video-captures-rw
  #      sudo garage bucket allow ${captureBucket} \
  #        --read --write --key radio-video-captures-rw
  #      sudo garage key info radio-video-captures-rw --show-secret
  #    Drop the access key + secret into `radio-video/rclone-env` via
  #    `sops secrets/secrets.yaml`:
  #      radio-video:
  #        rclone-env: |
  #          AWS_ACCESS_KEY_ID=...
  #          AWS_SECRET_ACCESS_KEY=...
  #    Smoke-test the mount after rebuild:
  #      sudo systemctl status rclone-radio-video-captures
  #      ls ${capturesDir}        # empty initially, fills as users /capture
  #    Exercise the prune unit once (this really deletes objects older than
  #    ${captureRetention} — harmless on a fresh bucket, but inspect first
  #    with `rclone delete --dry-run` if the bucket has data you care about):
  #      sudo systemctl start radio-video-captures-prune
  #
  # 1. Edit `channels` above and rebuild. Each entry becomes a sub-stream at
  #    /<name>/stream.m3u8; a `main` channel is auto-derived as the union and
  #    is the only one that accepts user submissions.
  #
  # 2. In the Pangolin dashboard, add a route:
  #      video.ericsharma.xyz  →  127.0.0.1:${toString hlsListenPort}
  #    The player page is served from the root and reads the channel from the
  #    URL hash, e.g.:
  #      https://video.ericsharma.xyz/            (defaults to main)
  #      https://video.ericsharma.xyz/#animation
  #      https://video.ericsharma.xyz/#vintage-nyc
  #    Direct manifest URLs are https://video.ericsharma.xyz/<channel>/stream.m3u8 .
  #
  # 3. Test from the host:
  #      curl -s http://127.0.0.1:${toString hlsListenPort}/main/stream.m3u8
  #      ffplay http://127.0.0.1:${toString hlsListenPort}/main/stream.m3u8
  #    Audio should match `mpv http://127.0.0.1:8000/stream` (existing radio).
  #
  # 4. Adjust `cacheTarget` (per channel) if downloads are slow or disk
  #    pressure shows up:
  #      - higher = more buffer against download stalls, more disk
  #      - lower  = leaner, but risks falling back to filler on a single failure
  #
  # 5. Submit a clip to main's priority queue (plays before any LoC item on
  #    main; never appears on other channels):
  #      curl -s -X POST http://127.0.0.1:${toString apiListenPort}/enqueue \
  #        -H 'Content-Type: application/json' \
  #        -d '{"url":"https://example.com/clip.mp4","title":"my clip"}'
  #      curl -s http://127.0.0.1:${toString apiListenPort}/queue    | jq
  #      curl -s http://127.0.0.1:${toString apiListenPort}/channels | jq
  #    For remote submissions, add a Pangolin route to 127.0.0.1:${toString apiListenPort}
  #    behind whatever auth you want (the orchestrator itself does no auth —
  #    binding to loopback is the only access control).
  #
  # 6. To iterate on the orchestrator code, edit /home/eric/eternatv,
  #    commit, then in this repo:
  #      nix flake update eternatv
  #      sudo nixos-rebuild switch --flake .#trigkey
}
