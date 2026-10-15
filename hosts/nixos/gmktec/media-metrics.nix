{ pkgs, ... }:

let
  textfileDir = "/var/lib/node-exporter-textfile";

  # `du` reports the LOGICAL size of each tree. A file that Sonarr hardlinked
  # from /data/usenet/complete into /data/media/tv is one set of blocks on disk
  # but is counted once in each tree here, so these numbers deliberately do not
  # add up to the filesystem's used space. Read them as "what this category is
  # worth", and read node_filesystem_avail_bytes for what the disk actually has
  # left. The dashboard shows both, side by side, for exactly this reason.
  collect = pkgs.writeShellScript "media-metrics" ''
    set -euo pipefail
    PATH=${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnused
        pkgs.findutils
      ]
    }

    out="${textfileDir}/media.prom"
    tmp="$out.$$"

    # A label value may not contain a bare backslash or double quote.
    esc() { sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

    size_of() { du -s --block-size=1 "$1" 2>/dev/null | cut -f1 || echo 0; }

    {
      echo '# HELP media_directory_size_bytes Logical size of a media directory as du reports it.'
      echo '# TYPE media_directory_size_bytes gauge'
      for pair in \
        "tv:/data/media/tv" \
        "movies:/data/media/movies" \
        "usenet_complete:/data/usenet/complete" \
        "usenet_incomplete:/data/usenet/incomplete"; do
        category="''${pair%%:*}"
        dir="''${pair#*:}"
        [ -d "$dir" ] || continue
        printf 'media_directory_size_bytes{category="%s",path="%s"} %s\n' \
          "$category" "$dir" "$(size_of "$dir")"
      done

      # Per-title sizes, so the dashboard can name what is actually big enough
      # to be worth deleting. One level deep only — season folders would
      # multiply the series count by ten for no extra insight.
      echo '# HELP media_title_size_bytes Logical size of one series or film directory.'
      echo '# TYPE media_title_size_bytes gauge'
      for pair in "tv:/data/media/tv" "movies:/data/media/movies"; do
        category="''${pair%%:*}"
        root="''${pair#*:}"
        [ -d "$root" ] || continue
        find "$root" -mindepth 1 -maxdepth 1 -type d -print0 \
          | while IFS= read -r -d ''' title_dir; do
              title="$(basename "$title_dir" | esc)"
              printf 'media_title_size_bytes{category="%s",title="%s"} %s\n' \
                "$category" "$title" "$(size_of "$title_dir")"
            done
      done

      echo '# HELP media_metrics_last_run_seconds Unix time this collector last finished.'
      echo '# TYPE media_metrics_last_run_seconds gauge'
      printf 'media_metrics_last_run_seconds %s\n' "$(date +%s)"
    } > "$tmp"

    # node_exporter reads this directory continuously. Move it into place so it
    # never sees a half-written file.
    mv "$tmp" "$out"
  '';
in
{
  # ── Media storage metrics ────────────────────────────────────────────────────
  # /data lives on the root filesystem, so node_exporter reports one number for
  # the whole disk and cannot say how much of it is TV, films, or downloads
  # still in flight. This fills that gap: a timer measures each directory and
  # writes Prometheus text into node_exporter's textfile directory, where the
  # existing scrape picks it up. No new service, no new port.
  #
  # Dashboard: hosts/nixos/optional/dashboards/media-storage.json (provisioned
  # on trigkey, where Grafana runs).

  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 root root -"
  ];

  services.prometheus.exporters.node = {
    enabledCollectors = [ "textfile" ];
    extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
  };

  systemd.services.media-metrics = {
    description = "Measure the media directories for Prometheus";
    unitConfig.RequiresMountsFor = "/data";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = collect;
      # du walks the whole library. Keep it off the CPU and disk that a
      # download or an import is using.
      Nice = 19;
      IOSchedulingClass = "idle";

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ReadOnlyPaths = [ "/data" ];
      ReadWritePaths = [ textfileDir ];
    };
  };

  systemd.timers.media-metrics = {
    description = "Measure the media directories every 15 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Run shortly after boot so a panel is never blank for long, then on a
      # fixed cadence. 15 minutes is far finer than the library changes, and du
      # over a warm page cache is cheap.
      OnBootSec = "3min";
      OnUnitActiveSec = "15min";
      Persistent = true;
    };
  };
}
