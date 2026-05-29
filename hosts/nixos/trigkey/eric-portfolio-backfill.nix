{ pkgs, ... }:

# Daily Yahoo Finance price backfill into the local `eric_portfolio` Postgres
# DB. The loader script lives at /home/eric/eric-portfolio-db/loader/ (a
# gitignored, local-only project) and runs incrementally — resumes from
# MAX(price_date) per ticker. ~2-3 minutes/day, network-bound.
#
# The python interpreter + deps are pinned via Nix; only the script content
# can change without a rebuild.

let
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.yfinance
    ps.psycopg
  ]);
in
{
  systemd.services.eric-portfolio-yahoo-backfill = {
    description = "Yahoo Finance price backfill for eric_portfolio DB";
    after = [
      "network-online.target"
      "postgresql.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "eric";
      Group = "users";
      ExecStart = "${pythonEnv}/bin/python3 /home/eric/eric-portfolio-db/loader/yahoo_backfill.py";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.eric-portfolio-yahoo-backfill = {
    description = "Daily Yahoo Finance price backfill (21:00 local)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 21:00:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };
}
