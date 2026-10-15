{ pkgs, ... }:

let
  fixer = pkgs.writers.writePython3 "kavita-epub-fix" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./kavita-epub-fix.py);
in
{
  # ── Kavita EPUB repair ───────────────────────────────────────────────────────
  # Every 5 minutes, rewrites EPUBs under /srv/kavita that Kavita cannot open.
  # Today that is one fault: an `<?xml version="1.1"?>` declaration, which
  # Kavita's .NET XML reader rejects, so the book never appears. See
  # ./kavita-epub-fix.py.
  #
  # It covers the whole library, not only Chaptarr imports, so a book copied in
  # by hand is repaired too. Kavita's folder watching (Settings → General)
  # then picks up the changed file; without it, the nightly scan does.
  #
  # State: /var/lib/kavita-epub-fix/originals holds the unmodified copy of each
  # repaired file. NOT backed up — the repaired file in /srv/kavita is, and the
  # change is a one-line XML header.
  #
  # To add another repair, add a check to needs_fix() in the script and look
  # for the exception in /srv/kavita/config/logs first.

  systemd.services.kavita-epub-fix = {
    description = "Repair EPUBs Kavita cannot open";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${fixer} /var/lib/kavita-epub-fix /srv/kavita/books /srv/kavita/comics /srv/kavita/manga";
      StateDirectory = "kavita-epub-fix";
      # Root only to keep each file's owner (eric, or NFS-squashed eric for
      # Chaptarr imports) when it replaces it. It can write nowhere else.
      ProtectSystem = "strict";
      ReadWritePaths = [
        "/srv/kavita/books"
        "/srv/kavita/comics"
        "/srv/kavita/manga"
      ];
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateNetwork = true;
      NoNewPrivileges = true;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.kavita-epub-fix = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
    };
  };
}
