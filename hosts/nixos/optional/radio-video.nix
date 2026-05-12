{
  config,
  lib,
  pkgs,
  ...
}:

let
  # ── Tunables ───────────────────────────────────────────────────────────────
  #
  # `videoCollections` is the list of loc.gov path segments the downloader
  # rotates through. Each entry is the `<slug>` in https://www.loc.gov/<slug>/.
  # Pick collections that surface film/video items — the downloader filters
  # with `fa=original-format:film,+video` regardless, but a collection without
  # any A/V items will simply yield no results.
  #
  # Useful starting points (uncomment a few):
  #   "free-to-use"          # rights-cleared media
  #   "audio-video"          # generic A/V landing
  #   "collections/national-screening-room"
  #   "collections/early-motion-pictures-1897-to-1920"
  #   "collections/inventing-entertainment-the-motion-pictures-and-sound-recordings-of-the-edison-companies"
  videoCollections = [
    "collections/origins-of-american-animation"
  ];

  audioStreamUrl = "http://127.0.0.1:8000/stream";
  hlsListenPort = 8088;
  cacheTarget = 3; # how many normalised mp4s to keep ready in the cache

  stateDir = "/var/lib/radio-video";
  cacheDir = "${stateDir}/cache";
  hlsDir = "${stateDir}/hls";
  fillerPath = "${stateDir}/filler.mp4";
  runtimeDir = "/run/radio-video";

  # ── Orchestrator script ────────────────────────────────────────────────────
  # Single long-running Python process that:
  #   1) keeps `cache/` populated with N normalised LoC videos
  #   2) runs one ffmpeg invocation per clip, writing to a single HLS manifest
  #      via `delete_segments+append_list` so viewers see a continuous stream
  #      across clip boundaries
  #   3) deletes each clip after playing it
  #   4) falls back to a generated black-screen filler if the cache is empty
  #
  # We deliberately do NOT use ffmpeg's concat demuxer with a FIFO playlist:
  # the demuxer reads its playlist to EOF before starting playback, which a
  # never-closed FIFO never reaches.
  orchestratorPy = pkgs.writeText "radio-video-orchestrator.py" ''
    #!/usr/bin/env python3
    """Radio-video orchestrator. See hosts/nixos/optional/radio-video.nix for design."""

    import json
    import logging
    import os
    import random
    import re
    import signal
    import socket
    import subprocess
    import sys
    import threading
    import time
    import urllib.parse
    from pathlib import Path

    # ── Config (Nix-interpolated) ──────────────────────────────────────────────
    CACHE_DIR    = Path("${cacheDir}")
    HLS_DIR      = Path("${hlsDir}")
    STATE_DIR    = Path("${stateDir}")
    RUNTIME_DIR  = Path("${runtimeDir}")
    FILLER_PATH  = Path("${fillerPath}")
    STATE_FILE   = STATE_DIR / "state.json"
    AUDIO_URL    = "${audioStreamUrl}"
    COLLECTIONS  = ${builtins.toJSON videoCollections}
    CACHE_TARGET = ${toString cacheTarget}
    HISTORY_MAX  = 500
    # LoC's WAF rejects requests with non-browser User-Agents (404 / 403).
    # Shelling out to curl also sidesteps any urllib TLS-fingerprint issues.
    HTTP_UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
               "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")

    log = logging.getLogger("radio-video")

    # ── systemd notify ────────────────────────────────────────────────────────
    def sd_notify(msg: str) -> None:
        addr = os.environ.get("NOTIFY_SOCKET")
        if not addr:
            return
        if addr.startswith("@"):
            addr = "\0" + addr[1:]
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as s:
                s.connect(addr)
                s.send(msg.encode())
        except OSError as e:
            log.warning("sd_notify failed: %s", e)

    # ── Persistent state ──────────────────────────────────────────────────────
    state_lock = threading.Lock()
    state: dict = {"history": [], "seg_num": 1000}

    def load_state() -> None:
        global state
        if STATE_FILE.exists():
            try:
                state = json.loads(STATE_FILE.read_text())
            except Exception as e:
                log.warning("could not load state: %s", e)
        state.setdefault("history", [])
        state.setdefault("seg_num", 1000)

    def save_state() -> None:
        tmp = STATE_FILE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(state))
        tmp.replace(STATE_FILE)

    def remember(item_id: str) -> None:
        with state_lock:
            h = state["history"]
            if item_id in h:
                h.remove(item_id)
            h.append(item_id)
            del h[:-HISTORY_MAX]
            save_state()

    def seen(item_id: str) -> bool:
        with state_lock:
            return item_id in state["history"]

    def reserve_seg_nums(count: int) -> int:
        # Persistent monotonically-increasing counter so segment filenames
        # never collide across the per-clip ffmpeg invocations or restarts.
        with state_lock:
            n = state["seg_num"]
            state["seg_num"] = n + count
            save_state()
            return n

    # ── HTTP via curl ─────────────────────────────────────────────────────────
    def http_get_json(url: str) -> dict:
        out = subprocess.check_output(
            ["curl", "-sfL", "--max-time", "30",
             "-A", HTTP_UA,
             "-H", "Accept: application/json",
             url],
            timeout=60,
        )
        return json.loads(out)

    # ── LoC discovery ─────────────────────────────────────────────────────────
    def loc_pick_item() -> dict | None:
        if not COLLECTIONS:
            log.error("videoCollections is empty — populate it in radio-video.nix")
            return None
        cols = list(COLLECTIONS)
        random.shuffle(cols)
        for col in cols:
            try:
                base = f"https://www.loc.gov/{col}/"
                params = {"fo": "json", "fa": "original-format:film,+video",
                          "c": "100", "sp": "1"}
                page1 = http_get_json(base + "?" + urllib.parse.urlencode(params, safe=",+"))
                pagination = page1.get("pagination") or {}
                total_pages = int(pagination.get("total") or 1) or 1
                page = random.randint(1, max(1, total_pages))
                if page == 1:
                    results = page1.get("results") or []
                else:
                    params["sp"] = str(page)
                    pn = http_get_json(base + "?" + urllib.parse.urlencode(params, safe=",+"))
                    results = pn.get("results") or []
            except Exception as e:
                log.warning("loc_pick %s failed: %s", col, e)
                continue
            random.shuffle(results)
            for item in results:
                iid = item.get("id") or item.get("url")
                if not iid or seen(iid):
                    continue
                # Search results carry the direct mp4 URL on resources[0].video;
                # no item-detail fetch needed.
                res_list = item.get("resources") or []
                video_url = (res_list[0].get("video") if res_list else None)
                if not video_url:
                    continue
                return {"id": iid,
                        "url": item.get("url") or iid,
                        "title": item.get("title", ""),
                        "video_url": video_url}
        return None

    # ── Download + normalize ──────────────────────────────────────────────────
    def item_slug(item_id: str) -> str:
        # LoC item ids look like "http://www.loc.gov/item/00694018/" — keep
        # the final path component (e.g. "00694018"). Sanitised for FS safety.
        last = item_id.rstrip("/").rsplit("/", 1)[-1] or "item"
        return re.sub(r"[^A-Za-z0-9._-]", "_", last)[:80]

    def download_and_normalize(item: dict) -> Path | None:
        slug = item_slug(item["id"])
        raw_dir = STATE_DIR / "raw"
        raw_dir.mkdir(parents=True, exist_ok=True)
        raw = raw_dir / f"{slug}.mp4"
        if raw.exists():
            try: raw.unlink()
            except OSError: pass

        # LoC publishes direct mp4 URLs on every item — no scraping needed.
        try:
            subprocess.run(
                ["curl", "-sfL", "--max-time", "1800",
                 "-A", HTTP_UA,
                 "-o", str(raw),
                 item["video_url"]],
                check=True, timeout=1800,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            log.warning("download failed for %s: %s", item["video_url"], e)
            if raw.exists():
                try: raw.unlink()
                except OSError: pass
            return None

        out = CACHE_DIR / f"{slug}.mp4"
        try:
            subprocess.run([
                "ffmpeg", "-y", "-nostdin", "-loglevel", "error",
                "-i", str(raw),
                "-vf", "scale=1280:720:force_original_aspect_ratio=decrease,"
                       "pad=1280:720:(ow-iw)/2:(oh-ih)/2,fps=24,setsar=1",
                "-c:v", "libx264", "-preset", "veryfast",
                "-profile:v", "high", "-level", "4.0",
                "-g", "96", "-keyint_min", "96", "-sc_threshold", "0",
                "-pix_fmt", "yuv420p",
                "-an",
                "-movflags", "+faststart",
                str(out),
            ], check=True, timeout=3600)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            log.warning("normalize failed for %s: %s", raw, e)
            if out.exists(): out.unlink()
            return None
        finally:
            try: raw.unlink()
            except OSError: pass

        remember(item["id"])
        log.info("ready: %s (%s)", out.name, item.get("title", ""))
        return out

    # ── Filler clip ───────────────────────────────────────────────────────────
    def ensure_filler() -> None:
        if FILLER_PATH.exists() and FILLER_PATH.stat().st_size > 0:
            return
        log.info("generating filler clip")
        subprocess.run([
            "ffmpeg", "-y", "-nostdin", "-loglevel", "error",
            "-f", "lavfi", "-i", "color=c=black:s=1280x720:d=30:r=24",
            "-c:v", "libx264", "-preset", "veryfast",
            "-profile:v", "high", "-level", "4.0",
            "-g", "96", "-keyint_min", "96", "-sc_threshold", "0",
            "-pix_fmt", "yuv420p",
            "-an",
            "-movflags", "+faststart",
            str(FILLER_PATH),
        ], check=True, timeout=120)

    def probe_duration(path: Path) -> float:
        try:
            out = subprocess.check_output(
                ["ffprobe", "-v", "error",
                 "-show_entries", "format=duration",
                 "-of", "csv=p=0", str(path)],
                timeout=30,
            )
            return float(out.strip())
        except Exception:
            return 30.0

    # ── Playout: one ffmpeg per clip, HLS append ──────────────────────────────
    shutdown = threading.Event()
    current_proc: subprocess.Popen | None = None
    proc_lock = threading.Lock()

    def build_playout_cmd(clip: Path, start_num: int) -> list[str]:
        return [
            "ffmpeg", "-nostdin", "-loglevel", "warning",
            "-fflags", "+genpts+discardcorrupt",
            "-re", "-i", str(clip),
            "-i", AUDIO_URL,
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", "libx264", "-preset", "veryfast",
            "-profile:v", "high", "-level", "4.0",
            "-pix_fmt", "yuv420p",
            "-g", "96", "-keyint_min", "96", "-sc_threshold", "0",
            "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "2",
            "-shortest",
            "-f", "hls",
            "-hls_time", "4",
            "-hls_list_size", "12",
            "-hls_flags", "delete_segments+append_list+independent_segments+program_date_time",
            "-hls_segment_type", "mpegts",
            "-hls_segment_filename", str(HLS_DIR / "seg-%05d.ts"),
            "-start_number", str(start_num),
            str(HLS_DIR / "stream.m3u8"),
        ]

    def play_clip(clip: Path) -> int:
        global current_proc
        duration = probe_duration(clip)
        reserve = max(8, int(duration / 4) + 4)
        start_num = reserve_seg_nums(reserve)
        log.info("playing %s (%.1fs, segs %d..%d)",
                 clip.name, duration, start_num, start_num + reserve - 1)
        cmd = build_playout_cmd(clip, start_num)
        with proc_lock:
            current_proc = subprocess.Popen(cmd)
            proc = current_proc
        rc = proc.wait()
        with proc_lock:
            current_proc = None
        if rc != 0 and not shutdown.is_set():
            log.warning("ffmpeg rc=%s for %s", rc, clip.name)
        return rc

    def playout_loop() -> None:
        backoff = 1.0
        while not shutdown.is_set():
            try:
                cands = sorted(CACHE_DIR.glob("*.mp4"))
                if cands:
                    clip = cands[0]
                    rc = play_clip(clip)
                    if rc == 0:
                        backoff = 1.0
                        try: clip.unlink()
                        except OSError: pass
                    else:
                        shutdown.wait(backoff)
                        backoff = min(backoff * 2, 30.0)
                else:
                    # No content ready — play filler. Don't delete it.
                    play_clip(FILLER_PATH)
            except Exception as e:
                log.exception("playout: %s", e)
                shutdown.wait(2)

    # ── Downloader thread ─────────────────────────────────────────────────────
    def downloader_loop() -> None:
        while not shutdown.is_set():
            try:
                ready = list(CACHE_DIR.glob("*.mp4"))
                if len(ready) >= CACHE_TARGET:
                    shutdown.wait(15)
                    continue
                item = loc_pick_item()
                if not item:
                    shutdown.wait(30)
                    continue
                download_and_normalize(item)
            except Exception as e:
                log.exception("downloader: %s", e)
                shutdown.wait(10)

    # ── Main ──────────────────────────────────────────────────────────────────
    def handle_signal(signum, _frame):
        log.info("signal %s — shutting down", signum)
        shutdown.set()
        with proc_lock:
            if current_proc and current_proc.poll() is None:
                current_proc.terminate()

    def main() -> int:
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s %(levelname)s %(message)s",
            stream=sys.stdout,
        )
        for d in (CACHE_DIR, HLS_DIR, STATE_DIR, RUNTIME_DIR):
            d.mkdir(parents=True, exist_ok=True)
        load_state()
        ensure_filler()

        signal.signal(signal.SIGTERM, handle_signal)
        signal.signal(signal.SIGINT, handle_signal)

        threads = [
            threading.Thread(target=downloader_loop, name="downloader", daemon=True),
            threading.Thread(target=playout_loop,    name="playout",    daemon=True),
        ]
        for t in threads:
            t.start()

        sd_notify("READY=1")
        log.info("ready")

        shutdown.wait()
        for t in threads:
            t.join(timeout=10)
        return 0

    if __name__ == "__main__":
        sys.exit(main())
  '';
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

  # ── State dirs ────────────────────────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d ${stateDir}      0755 radio-video radio-video -"
    "d ${cacheDir}      0755 radio-video radio-video -"
    "d ${hlsDir}        0755 radio-video radio-video -"
    "d ${stateDir}/raw  0755 radio-video radio-video -"
    "d ${runtimeDir}    0755 radio-video radio-video -"
  ];

  # ── Orchestrator service ──────────────────────────────────────────────────
  systemd.services.radio-video-orchestrator = {
    description = "LoC video downloader + ffmpeg HLS supervisor (radio.ericsharma.xyz video sidecar)";
    after = [
      "network-online.target"
      "icecast.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "icecast.service" ];
    wantedBy = [ "multi-user.target" ];

    path = [
      pkgs.ffmpeg-headless
      pkgs.python3
      pkgs.curl
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "notify";
      NotifyAccess = "main";
      User = "radio-video";
      Group = "radio-video";
      ExecStart = "${pkgs.python3}/bin/python3 ${orchestratorPy}";
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
      ReadWritePaths = [ stateDir runtimeDir ];
    };
  };

  # ── nginx: serve HLS on 127.0.0.1:8088 ─────────────────────────────────────
  services.nginx = {
    enable = true;
    virtualHosts."radio-video-hls" = {
      listen = [ { addr = "127.0.0.1"; port = hlsListenPort; } ];
      root = hlsDir;
      extraConfig = ''
        add_header Cache-Control no-cache always;
        add_header Access-Control-Allow-Origin * always;
        types {
          application/vnd.apple.mpegurl m3u8;
          video/mp2t                    ts;
        }
        default_type application/octet-stream;
      '';
    };
  };

  # ── Post-deploy one-time setup (manual) ───────────────────────────────────
  #
  # 1. Edit `videoCollections` above and rebuild. Until populated, the
  #    downloader logs an error and only the black-screen filler will play.
  #
  # 2. In the Pangolin dashboard, add a route:
  #      video.ericsharma.xyz  →  127.0.0.1:${toString hlsListenPort}
  #    HLS manifest URL will be:
  #      https://video.ericsharma.xyz/stream.m3u8
  #
  # 3. Test from the host:
  #      curl -s http://127.0.0.1:${toString hlsListenPort}/stream.m3u8
  #      ffplay http://127.0.0.1:${toString hlsListenPort}/stream.m3u8
  #    Audio should match `mpv http://127.0.0.1:8000/stream` (existing radio).
  #
  # 4. Adjust `cacheTarget` if downloads are slow or disk pressure shows up:
  #      - higher = more buffer against download stalls, more disk
  #      - lower  = leaner, but risks falling back to filler on a single failure
}
