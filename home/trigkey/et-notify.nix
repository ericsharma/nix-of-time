{ pkgs, ... }:

# Push notifications to the E.T. iOS app when a manymux session rings its bell.
#
# Bells mean "come back": a long shell command finished (../common/shell.nix
# rings after >= 15 s) or Claude Code wants input (Claude's
# preferredNotifChannel = terminal_bell). Each machine's etd follows its own
# manymux node and sends the bell to trigkey's etd, which runs
# `et-notify --manymux`; that sends an APNs push to every phone that
# registered a token in ~/.config/et/devices/ (the app writes it there).
# The tmux path (`et-notify <window>`) stays for E.T.'s tmux mode, but no
# tmux hook runs it here any more (the tmux workspace is gone; see `ws`).
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
        import os
        import pathlib
        import re
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


        def app_open(what):
            # E.T. open: it alerts by itself.
            if FOREGROUND.exists() and time.time() - FOREGROUND.stat().st_mtime < FOREGROUND_FRESH:
                log(f"skip {what}: E.T. is open")
                return True
            return False


        def rate_limited(key, what):
            # A burst of bells is one notification.
            STATE.mkdir(parents=True, exist_ok=True)
            stamp = STATE / f"last-{key}"
            if stamp.exists() and time.time() - stamp.stat().st_mtime < MIN_INTERVAL:
                log(f"skip {what}: rate limit")
                return True
            stamp.touch()
            return False


        def tmux_main(window_id):
            # The pane is looked up here: in a hook, #{pane_id} is the client's
            # current pane, not the one in the window that rang.
            pane_id = tmux("display-message", "-p", "-t", window_id, "#{pane_id}").strip()
            if app_open(window_id):
                return
            name = tmux("display-message", "-p", "-t", window_id, "#{window_name}").strip() or window_id
            session = tmux("display-message", "-p", "-t", window_id, "#{session_name}").strip()
            if rate_limited(window_id.lstrip("@"), window_id):
                return

            lines = [x.strip() for x in tmux("capture-pane", "-p", "-t", pane_id, "-S", "-80").splitlines() if x.strip()]
            if "claude" in name.lower():
                # Claude Code starts its messages with "⏺"; quote the last one.
                said = [x.split("⏺", 1)[1].strip() for x in lines if "⏺" in x]
                body = f"Claude: {said[-1][:150]}" if said and said[-1] else "Claude is waiting for you"
            else:
                body = lines[-1][:160] if lines else "Finished"
            # server/session/window let a tap open this exact window.
            push(name, body, {"session": session, "window": name}, f"{window_id.lstrip('@')}-{name}",
                 f"{name} ({window_id} in {session})")


        def manymux_main():
            # Run by etd for a manymux session that wants someone while nobody
            # is attached (etd crates/etd/src/events.rs sets these).
            machine = os.environ.get("ETD_MACHINE", "")
            session = os.environ.get("ETD_SESSION", "")
            name = f"{machine}/{session}"
            if app_open(name):
                return
            key = re.sub(r"[^A-Za-z0-9._-]", "_", f"mm-{machine}-{session}")
            if rate_limited(key, name):
                return
            body = os.environ.get("ETD_BODY") or os.environ.get("ETD_TITLE") or "Finished"
            if "claude" in session.lower() and body in ("Finished", session):
                body = "Claude is waiting for you"
            # machine/session let a tap open this exact session.
            push(name, body[:160], {"manymux": {"machine": machine, "session": session}}, key, name)


        def push(name, body, extra, collapse, what):
            devices = sorted(DEVICES.glob("*.json")) if DEVICES.exists() else []
            if not devices:
                log("no registered devices")
                return
            token = apns_jwt()
            for path in devices:
                device = json.loads(path.read_text())
                # The server is the phone's own ID for this machine.
                payload = json.dumps({
                    "aps": {"alert": {"title": f"🔔 {name}", "body": body}, "sound": "default",
                            "thread-id": name},
                    "server": device.get("server"),
                    **extra,
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
                    "-H", f"apns-collapse-id: {collapse}"[:80],
                    "--data", payload,
                    f"https://{host}/3/device/{device['token']}",
                ], capture_output=True, text=True)
                log(f"{what}: {path.stem} {result.stdout.strip() or result.stderr.strip()}")


        try:
            if sys.argv[1:2] == ["--manymux"]:
                manymux_main()
            else:
                tmux_main(sys.argv[1])
        except Exception as error:  # never break tmux or etd; just record it
            log(f"error: {error!r}")
      '';
in
{
  home.packages = [ et-notify ];

  # manymux sessions: etd follows trigkey's manymux node (which also carries
  # the machines it watches) and runs this for a bell, notification or failed
  # exit that nobody attached saw. Quoted: the value has a space.
  systemd.user.services.etd.Service.Environment = [
    ''"ETD_NOTIFY_COMMAND=${et-notify}/bin/et-notify --manymux"''
  ];
}
