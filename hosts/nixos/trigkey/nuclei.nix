{
  config,
  lib,
  pkgs,
  ...
}:

# External security checks of every public Pangolin resource. Two jobs:
#
# - pangolin-sso-check (hourly): every resource whose policy says SSO must
#   answer an anonymous request with 401 or a redirect to Pangolin's auth page.
#   This is the regression that left SSO off cluster-wide from 2026-11-19 to
#   2026-11-25 (pangolin-node/cluster.nix, `badger-dashboard`).
# - nuclei-scan (weekly): Nuclei against the same hostnames, from outside.
#   Traffic leaves trigkey and comes back through the Pangolin nodes, so it
#   sees what the internet sees, SSO included. Never point it at loopback.
#
# Both read the hostname list from the `pangolin` database on this host, so a
# route added in the dashboard is checked on the next run with no Nix edit.
# Results go to node_exporter's textfile directory; alert rules are in
# optional/monitoring.nix (group "security"). Use and triage:
# docs/services/nuclei.md.
let
  textfileDir = "/var/lib/node-exporter-textfile";
  stateDir = "/var/lib/nuclei";
  psql = "${config.services.postgresql.package}/bin/psql";
  templates = "${pkgs.nuclei-templates}/share/nuclei-templates";

  # Accepted findings, by template id. Each needs a reason.
  ignoredTemplates = [ ];

  # Runs as root (the `+` prefix): only the postgres role can read the
  # pangolin database over the socket.
  listTargets = pkgs.writeShellScript "pangolin-targets" ''
    set -euo pipefail
    q() {
      ${pkgs.util-linux}/bin/runuser -u postgres -- ${psql} -d pangolin -AtX -c "$1" 2>/dev/null
    }
    q "select \"fullDomain\" from resources
       where \"fullDomain\" is not null and enabled and mode = 'http'
       order by 1" > "$1/targets.txt.tmp"
    q "select r.\"fullDomain\" from resources r
       join \"resourcePolicies\" p
         on p.\"resourcePolicyId\" = coalesce(r.\"resourcePolicyId\", r.\"defaultResourcePolicyId\")
       where r.\"fullDomain\" is not null and r.enabled and r.mode = 'http' and p.sso
       order by 1" > "$1/sso-targets.txt.tmp"
    # An empty list means the query broke, not that nothing is public.
    [ -s "$1/targets.txt.tmp" ] || { echo "no targets from pangolin db" >&2; exit 1; }
    mv "$1/targets.txt.tmp" "$1/targets.txt"
    mv "$1/sso-targets.txt.tmp" "$1/sso-targets.txt"
  '';

  ssoCheck = pkgs.writeShellScript "pangolin-sso-check" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
      ]
    }
    out="${textfileDir}/pangolin_sso.prom"
    tmp="$STATE_DIRECTORY/pangolin_sso.prom"
    {
      echo '# HELP pangolin_sso_enforced 1 if an anonymous request is refused (401 or redirect to Pangolin auth).'
      echo '# TYPE pangolin_sso_enforced gauge'
      while read -r host; do
        [ -n "$host" ] || continue
        # Browser-like Accept so badger answers with its redirect, not a bare 401.
        res=$(curl -s -o /dev/null -m 15 -H 'Accept: text/html' \
          -w '%{http_code} %{redirect_url}' "https://$host/" || echo "000 ")
        code=''${res%% *}; loc=''${res#* }
        ok=0
        case "$code" in
          401) ok=1 ;;
          30[1-8]) case "$loc" in https://pangolin.ericsharma.xyz/auth/*) ok=1 ;; esac ;;
        esac
        printf 'pangolin_sso_enforced{host="%s",code="%s"} %s\n' "$host" "$code" "$ok"
      done < "$STATE_DIRECTORY/sso-targets.txt"
      echo '# HELP pangolin_sso_check_last_run_seconds Unix time the SSO check last finished.'
      echo '# TYPE pangolin_sso_check_last_run_seconds gauge'
      echo "pangolin_sso_check_last_run_seconds $(date +%s)"
    } > "$tmp"
  '';

  scan = pkgs.writeShellScript "nuclei-scan" ''
    set -euo pipefail
    export HOME="$STATE_DIRECTORY"
    # Automatic scan (-as) only reads templates from a real directory under
    # $HOME; a symlink into the store is not walked. Copy once per version.
    if [ "$(cat "$HOME/templates.version" 2>/dev/null)" != "${templates}" ]; then
      rm -rf "$HOME/nuclei-templates"
      cp -r --no-preserve=mode ${templates} "$HOME/nuclei-templates"
      echo "${templates}" > "$HOME/templates.version"
    fi
    mkdir -p "$HOME/.config/nuclei"
    touch "$HOME/.config/nuclei/.nuclei-ignore"

    # -as: Wappalyzer fingerprint first, then only templates for what it
    # found. All templates x 42 hosts at this rate would take ~6 h.
    # -rl 30: every request lands on a 1 GB VPS that proxies everything.
    ${pkgs.nuclei}/bin/nuclei \
      -l "$HOME/targets.txt" \
      -ud "$HOME/nuclei-templates" \
      -as \
      -etags intrusive,dos,fuzz \
      ${
        lib.optionalString (ignoredTemplates != [ ]) "-eid ${lib.concatStringsSep "," ignoredTemplates}"
      } \
      -rl 30 -c 10 \
      -duc -ni -nc -silent \
      -jsonl -o "$HOME/findings.jsonl.new"
    mv "$HOME/findings.jsonl.new" "$HOME/findings.jsonl"
  '';

  # Runs as root after the scan to write into node_exporter's directory.
  scanMetrics = pkgs.writeShellScript "nuclei-metrics" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.jq
      ]
    }
    f="${stateDir}/findings.jsonl"
    {
      echo '# HELP nuclei_finding One Nuclei finding from the last scan.'
      echo '# TYPE nuclei_finding gauge'
      jq -r '[.host, ."template-id", .info.severity] | @tsv' "$f" | sort -u |
        while IFS=$'\t' read -r host tid sev; do
          printf 'nuclei_finding{host="%s",template="%s",severity="%s"} 1\n' "$host" "$tid" "$sev"
        done
      echo '# HELP nuclei_last_run_timestamp_seconds Unix time the last scan finished.'
      echo '# TYPE nuclei_last_run_timestamp_seconds gauge'
      echo "nuclei_last_run_timestamp_seconds $(date +%s)"
    } > "${textfileDir}/nuclei.prom.tmp"
    mv "${textfileDir}/nuclei.prom.tmp" "${textfileDir}/nuclei.prom"
  '';

  hardening = {
    DynamicUser = true;
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictSUIDSGID = true;
  };
in
{
  systemd.services.pangolin-sso-check = {
    description = "Check that Pangolin SSO refuses anonymous requests";
    after = [
      "network-online.target"
      "postgresql.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = hardening // {
      Type = "oneshot";
      # Own state dir: sharing nuclei's would make systemd re-chown the
      # template copy between the two dynamic users on every start.
      StateDirectory = "pangolin-sso-check";
      ExecStartPre = "+${listTargets} /var/lib/pangolin-sso-check";
      ExecStart = ssoCheck;
      ExecStartPost = "+${pkgs.coreutils}/bin/mv /var/lib/pangolin-sso-check/pangolin_sso.prom ${textfileDir}/pangolin_sso.prom";
    };
  };

  systemd.timers.pangolin-sso-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };

  systemd.services.nuclei-scan = {
    description = "Nuclei scan of the public Pangolin resources";
    after = [
      "network-online.target"
      "postgresql.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = hardening // {
      Type = "oneshot";
      StateDirectory = "nuclei";
      ExecStartPre = "+${listTargets} ${stateDir}";
      ExecStart = scan;
      ExecStartPost = "+${scanMetrics}";
      Nice = 19;
      TimeoutStartSec = "3h";
    };
  };

  systemd.timers.nuclei-scan = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 04:00";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };
}
