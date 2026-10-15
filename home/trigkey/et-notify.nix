{ pkgs, ... }:

# Push notifications to the E.T. iOS app when a tmux window rings its bell.
#
# Bells mean "come back": a long shell command finished (../common/shell.nix
# rings after >= 15 s) or Claude Code wants input (Claude's
# preferredNotifChannel = terminal_bell, on any machine — a bell from an ssh
# pane reaches this tmux too). tmux's alert-bell hook runs et-notify, which
# sends an APNs push to every phone that registered a token in
# ~/.config/et/devices/ (the app writes it there over SSH after attaching).
#
# No push while E.T. is open: the app vibrates itself. "Open" means E.T.
# touched ~/.local/state/et-notify/foreground in the last minute (it does
# every 20 s while connected). An attached control client is not proof:
# when iOS kills the app, its SSH session can linger for hours.
let
  apnsKeyId = "K5P349DQTD"; # Sandbox & Production
  teamId = "9MY2559FS4";
  apnsKeyPath = "/run/secrets/et-apns-key"; # hosts/nixos/optional/et-push.nix

  et-notify =
    pkgs.writers.writePython3Bin "et-notify"
      {
        libraries = [ pkgs.python3Packages.cryptography ];
        flakeIgnore = [ "E501" ];
      }
      ''
        import base64
        import json
        import pathlib
        import subprocess
        import sys
        import time

        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

        TMUX = "${pkgs.tmux}/bin/tmux"
        CURL = "${pkgs.curl}/bin/curl"
        KEY_ID = "${apnsKeyId}"
        TEAM_ID = "${teamId}"
        KEY_PATH = "${apnsKeyPath}"
        DEVICES = pathlib.Path.home() / ".config/et/devices"
        STATE = pathlib.Path.home() / ".local/state/et-notify"
        MIN_INTERVAL = 10  # seconds between pushes for the same window
        FOREGROUND = STATE / "foreground"  # touched by E.T. while it is open
        FOREGROUND_FRESH = 60  # seconds


        def log(msg):
            STATE.mkdir(parents=True, exist_ok=True)
            path = STATE / "log"
            if path.exists() and path.stat().st_size > 200_000:
                path.rename(STATE / "log.1")
            with path.open("a") as f:
                f.write(f"{time.strftime('%F %T')} {msg}\n")


        def tmux(*args):
            return subprocess.run([TMUX, *args], capture_output=True, text=True).stdout


        def b64(data):
            return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


        def apns_jwt():
            key = serialization.load_pem_private_key(pathlib.Path(KEY_PATH).read_bytes(), password=None)
            header = b64(json.dumps({"alg": "ES256", "kid": KEY_ID}).encode())
            claims = b64(json.dumps({"iss": TEAM_ID, "iat": int(time.time())}).encode())
            signing_input = f"{header}.{claims}".encode()
            r, s = decode_dss_signature(key.sign(signing_input, ec.ECDSA(hashes.SHA256())))
            return f"{header}.{claims}.{b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


        def main():
            window_id = sys.argv[1]
            # The pane is looked up here: in a hook, #{pane_id} is the client's
            # current pane, not the one in the window that rang.
            pane_id = tmux("display-message", "-p", "-t", window_id, "#{pane_id}").strip()
            # E.T. open: it alerts by itself.
            if FOREGROUND.exists() and time.time() - FOREGROUND.stat().st_mtime < FOREGROUND_FRESH:
                log(f"skip {window_id}: E.T. is open")
                return
            name = tmux("display-message", "-p", "-t", window_id, "#{window_name}").strip() or window_id
            session = tmux("display-message", "-p", "-t", window_id, "#{session_name}").strip()

            # Rate limit per window (a burst of bells is one notification).
            STATE.mkdir(parents=True, exist_ok=True)
            stamp = STATE / f"last-{window_id.lstrip('@')}"
            if stamp.exists() and time.time() - stamp.stat().st_mtime < MIN_INTERVAL:
                log(f"skip {window_id}: rate limit")
                return
            stamp.touch()

            lines = [x.strip() for x in tmux("capture-pane", "-p", "-t", pane_id, "-S", "-80").splitlines() if x.strip()]
            if "claude" in name.lower():
                # Claude Code starts its messages with "⏺"; quote the last one.
                said = [x.split("⏺", 1)[1].strip() for x in lines if "⏺" in x]
                body = f"Claude: {said[-1][:150]}" if said and said[-1] else "Claude is waiting for you"
            else:
                body = lines[-1][:160] if lines else "Finished"

            devices = sorted(DEVICES.glob("*.json")) if DEVICES.exists() else []
            if not devices:
                log("no registered devices")
                return
            token = apns_jwt()
            for path in devices:
                device = json.loads(path.read_text())
                # server/session/window let a tap open this exact window; the
                # server is the phone's own ID for this machine.
                payload = json.dumps({
                    "aps": {"alert": {"title": f"🔔 {name}", "body": body}, "sound": "default",
                            "thread-id": name},
                    "server": device.get("server"),
                    "session": session,
                    "window": name,
                })
                host = "api.sandbox.push.apple.com" if device.get("environment") == "development" else "api.push.apple.com"
                result = subprocess.run([
                    CURL, "--silent", "--http2", "--max-time", "10",
                    "--write-out", "%{http_code}", "--output", "-",
                    "-H", f"authorization: bearer {token}",
                    "-H", f"apns-topic: {device.get('bundle', 'xyz.ericsharma.et')}",
                    "-H", "apns-push-type: alert",
                    "-H", "apns-priority: 10",
                    # A newer alert from the same window replaces the older one.
                    "-H", f"apns-collapse-id: {window_id.lstrip('@')}-{name}"[:80],
                    "--data", payload,
                    f"https://{host}/3/device/{device['token']}",
                ], capture_output=True, text=True)
                log(f"{name} ({window_id} in {session}): {path.stem} {result.stdout.strip() or result.stderr.strip()}")


        try:
            main()
        except Exception as error:  # never break tmux; just record it
            log(f"error: {error!r}")
      '';
in
{
  home.packages = [ et-notify ];

  # bell-action any: alert on bells in every window, including the current
  # one (you may be looking at the laptop, not the phone).
  programs.tmux.extraConfig = ''
    set -g monitor-bell on
    set -g bell-action any
    # #{hook_window} is the window that rang. Plain #{window_id} here would
    # be the session's current window, and the notification would open that.
    set-hook -g alert-bell 'run-shell -b "${et-notify}/bin/et-notify #{hook_window}"'
  '';
}
