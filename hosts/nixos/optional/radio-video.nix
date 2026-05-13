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
    "collections/early-films-of-new-york-1898-to-1906"
  ];

  audioStreamUrl = "http://127.0.0.1:8000/stream";
  hlsListenPort = 8088;
  apiListenPort = 8089; # enqueue API, 127.0.0.1 only — expose via Pangolin if remote
  cacheTarget = 3; # how many normalised mp4s to keep ready in the cache

  stateDir = "/var/lib/radio-video";
  cacheDir = "${stateDir}/cache";
  priorityDir = "${stateDir}/priority"; # user-submitted clips, drained FIFO before cache
  hlsDir = "${stateDir}/hls";
  fillerPath = "${stateDir}/filler.mp4";
  runtimeDir = "/run/radio-video";

  # ── Static HLS player page ─────────────────────────────────────────────────
  # Lives in its own derivation so the Python orchestrator's `''` indent
  # block doesn't have to coexist with HTML lines that start at column 0.
  playerHtml = pkgs.writeText "radio-video-player.html" ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>radio.ericsharma.xyz</title>
    <style>
      html, body { margin: 0; height: 100%; background: #000; color: #fff;
                   font-family: ui-sans-serif, system-ui, sans-serif; }
      body { display: flex; align-items: center; justify-content: center; }
      video { width: 100%; height: 100%; object-fit: contain; background: #000; }
      #hint { position: fixed; left: 0; right: 0; bottom: 1.5rem; text-align: center;
              font-size: 0.85rem; opacity: 0.6; pointer-events: none;
              transition: opacity 0.5s; }
      #hint.gone { opacity: 0; }
    </style>
    </head>
    <body>
    <video id="v" autoplay muted playsinline controls></video>
    <div id="hint">tap / click anywhere for audio</div>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@1"></script>
    <script>
      (function () {
        var v = document.getElementById('v');
        var hint = document.getElementById('hint');
        var src = '/stream.m3u8';
        if (window.Hls && Hls.isSupported()) {
          var hls = new Hls({
            lowLatencyMode: false,
            liveSyncDuration: 12,
            liveMaxLatencyDuration: 30,
            manifestLoadingMaxRetry: 10,
            levelLoadingMaxRetry: 10,
            fragLoadingMaxRetry: 10
          });
          hls.loadSource(src);
          hls.attachMedia(v);
          hls.on(Hls.Events.ERROR, function (_evt, data) {
            if (!data.fatal) return;
            if (data.type === Hls.ErrorTypes.NETWORK_ERROR) hls.startLoad();
            else if (data.type === Hls.ErrorTypes.MEDIA_ERROR) hls.recoverMediaError();
          });
        } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
          v.src = src;
        }
        function unmute() {
          v.muted = false;
          v.play().catch(function () {});
          hint.classList.add('gone');
          document.body.removeEventListener('click', unmute);
          document.body.removeEventListener('touchstart', unmute);
        }
        document.body.addEventListener('click', unmute);
        document.body.addEventListener('touchstart', unmute);
      })();
    </script>
    </body>
    </html>
  '';

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

    import hashlib
    import http.server
    import json
    import logging
    import os
    import queue
    import random
    import re
    import signal
    import socket
    import socketserver
    import subprocess
    import sys
    import threading
    import time
    import urllib.parse
    from pathlib import Path

    # ── Config (Nix-interpolated) ──────────────────────────────────────────────
    CACHE_DIR    = Path("${cacheDir}")
    PRIORITY_DIR = Path("${priorityDir}")
    HLS_DIR      = Path("${hlsDir}")
    STATE_DIR    = Path("${stateDir}")
    RUNTIME_DIR  = Path("${runtimeDir}")
    FILLER_PATH  = Path("${fillerPath}")
    STATE_FILE   = STATE_DIR / "state.json"
    AUDIO_URL    = "${audioStreamUrl}"
    API_PORT     = ${toString apiListenPort}
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
    def loc_pick_item(allow_seen: bool = False) -> dict | None:
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
                if not iid:
                    continue
                if not allow_seen and seen(iid):
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

    # Serialises the LoC downloader and user-submission workers so they don't
    # fight for bandwidth or hammer ffmpeg in parallel.
    download_lock = threading.Lock()

    def download_and_normalize(item: dict, target_dir: Path = CACHE_DIR,
                                skip_seen: bool = False) -> Path | None:
        slug = item_slug(item["id"])
        raw_dir = STATE_DIR / "raw"
        raw_dir.mkdir(parents=True, exist_ok=True)
        raw = raw_dir / f"{slug}.mp4"
        if raw.exists():
            try: raw.unlink()
            except OSError: pass

        with download_lock:
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

            out = target_dir / f"{slug}.mp4"
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

        if not skip_seen:
            remember(item["id"])
        log.info("ready: %s (%s)", out.name, item.get("title", ""))
        return out

    # ── User submissions ─────────────────────────────────────────────────────
    # Submission ids are timestamp-prefixed so the priority dir's sorted glob
    # drains FIFO. The id doubles as the on-disk slug.
    submission_queue: queue.Queue = queue.Queue()

    def submission_to_item(url: str, title: str | None) -> dict:
        ts_ms = int(time.time() * 1000)
        short = hashlib.sha1(url.encode()).hexdigest()[:8]
        pseudo_id = f"{ts_ms:013d}-{short}"
        return {"id": pseudo_id, "url": url,
                "title": title or url, "video_url": url}

    def submission_worker() -> None:
        while not shutdown.is_set():
            try:
                item = submission_queue.get(timeout=1.0)
            except queue.Empty:
                continue
            try:
                log.info("submission: %s (%s)", item["title"], item["video_url"])
                download_and_normalize(item, target_dir=PRIORITY_DIR, skip_seen=True)
            except Exception as e:
                log.exception("submission failed: %s", e)

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

    # ── Player page ───────────────────────────────────────────────────────────
    # Without this, hitting the bare hostname 403s (no index, autoindex off),
    # and opening stream.m3u8 directly relies on the browser's native HLS
    # player which fetches the manifest only once. hls.js polls the manifest
    # continuously and handles DISCONTINUITY across clip boundaries.
    PLAYER_HTML_SRC = Path("${playerHtml}")

    def ensure_player_html() -> None:
        target = HLS_DIR / "index.html"
        content = PLAYER_HTML_SRC.read_text()
        try:
            if target.exists() and target.read_text() == content:
                return
        except OSError:
            pass
        tmp = target.with_suffix(".html.tmp")
        tmp.write_text(content)
        tmp.replace(target)
        log.info("wrote player page to %s", target)

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

    # ── Playout: master ffmpeg + sequential per-clip remuxers ────────────────
    #
    # ONE long-running "master" ffmpeg writes the HLS manifest. It reads an
    # mpegts video stream from stdin (fed by Python from sequential per-clip
    # remuxers) plus the icecast audio. Because the master never exits, the
    # manifest is appended to continuously across clip boundaries — no
    # restart gap, no PTS reset, no DISCONTINUITY marker.
    #
    # Per-clip remuxers stream-copy each normalised mp4 into mpegts with
    # `-output_ts_offset` set to the running play-time, so successive clips
    # produce a single monotonic PTS timeline.
    shutdown = threading.Event()
    current_master: subprocess.Popen | None = None
    current_remuxer: subprocess.Popen | None = None
    proc_lock = threading.Lock()

    def build_master_cmd(start_num: int) -> list[str]:
        return [
            "ffmpeg", "-nostdin", "-loglevel", "warning",
            "-fflags", "+genpts+discardcorrupt",
            "-f", "mpegts", "-i", "pipe:0",
            "-re", "-i", AUDIO_URL,
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", "copy",
            "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "2",
            "-f", "hls",
            "-hls_time", "4",
            "-hls_list_size", "12",
            "-hls_flags", "delete_segments+append_list+independent_segments+program_date_time+omit_endlist",
            "-hls_segment_type", "mpegts",
            "-hls_segment_filename", str(HLS_DIR / "seg-%05d.ts"),
            "-start_number", str(start_num),
            str(HLS_DIR / "stream.m3u8"),
        ]

    def build_remuxer_cmd(clip: Path, ts_offset: float) -> list[str]:
        return [
            "ffmpeg", "-nostdin", "-loglevel", "error",
            "-re", "-i", str(clip),
            "-c:v", "copy", "-an",
            "-f", "mpegts",
            "-muxpreload", "0", "-muxdelay", "0",
            "-output_ts_offset", f"{ts_offset:.3f}",
            "pipe:1",
        ]

    def start_master() -> subprocess.Popen:
        global current_master
        # Reserve a big block of segment numbers per master invocation so
        # any prior segments lingering on disk can't collide with new ones.
        start_num = reserve_seg_nums(100_000)
        log.info("starting master ffmpeg (start_number=%d)", start_num)
        proc = subprocess.Popen(
            build_master_cmd(start_num),
            stdin=subprocess.PIPE,
            bufsize=0,
        )
        with proc_lock:
            current_master = proc
        return proc

    def pick_next_clip() -> Path:
        # User submissions land in PRIORITY_DIR with timestamp-prefixed names,
        # so the sorted glob drains them FIFO before falling back to the LoC
        # cache, then to the filler clip.
        pri = sorted(PRIORITY_DIR.glob("*.mp4"))
        if pri:
            return pri[0]
        cands = sorted(CACHE_DIR.glob("*.mp4"))
        return cands[0] if cands else FILLER_PATH

    def feed_clip(master: subprocess.Popen, clip: Path, ts_offset: float) -> float:
        """Pipe one clip's mpegts into the master. Returns clip duration on success."""
        global current_remuxer
        duration = probe_duration(clip)
        log.info("feeding %s (%.1fs, offset=%.1fs)", clip.name, duration, ts_offset)
        remuxer = subprocess.Popen(
            build_remuxer_cmd(clip, ts_offset),
            stdout=subprocess.PIPE,
            bufsize=0,
        )
        with proc_lock:
            current_remuxer = remuxer
        try:
            while True:
                chunk = remuxer.stdout.read(65536)
                if not chunk:
                    break
                try:
                    master.stdin.write(chunk)
                    master.stdin.flush()
                except (BrokenPipeError, OSError):
                    log.warning("master pipe broken while feeding %s", clip.name)
                    if remuxer.poll() is None:
                        remuxer.terminate()
                    raise
        finally:
            try:
                remuxer.stdout.close()
            except OSError:
                pass
            remuxer.wait()
            with proc_lock:
                current_remuxer = None
        return duration

    def playout_loop() -> None:
        backoff = 1.0
        while not shutdown.is_set():
            try:
                master = start_master()
                ts_offset = 0.0
                while not shutdown.is_set() and master.poll() is None:
                    clip = pick_next_clip()
                    try:
                        played = feed_clip(master, clip, ts_offset)
                    except (BrokenPipeError, OSError):
                        # master died mid-feed; outer loop will respawn
                        break
                    ts_offset += played
                    if clip != FILLER_PATH and clip.exists():
                        try: clip.unlink()
                        except OSError: pass
                    backoff = 1.0
                if master.poll() is None:
                    # shutdown requested
                    try: master.stdin.close()
                    except OSError: pass
                    master.terminate()
                rc = master.wait()
                if not shutdown.is_set():
                    log.warning("master ffmpeg exited rc=%s, restarting", rc)
                    shutdown.wait(backoff)
                    backoff = min(backoff * 2, 30.0)
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
                    # Either LoC is unreachable or every result on the random
                    # page we hit is in `seen`. Retry once allowing seen items
                    # before sleeping — `remember()` will push the re-picked
                    # item to the end and roll the oldest entry off naturally,
                    # so the history stays a rolling window instead of a hard
                    # wall that strands us in filler-loop forever.
                    item = loc_pick_item(allow_seen=True)
                    if item:
                        log.info("history exhausted — replaying %s", item.get("title", item["id"]))
                if not item:
                    shutdown.wait(30)
                    continue
                download_and_normalize(item)
            except Exception as e:
                log.exception("downloader: %s", e)
                shutdown.wait(10)

    # ── HTTP API ──────────────────────────────────────────────────────────────
    # Bound to 127.0.0.1; expose via a Pangolin route if remote access is wanted.
    # Endpoints:
    #   POST /enqueue {"url": "...", "title": "?"}  -> 202 {queued, slug}
    #   GET  /queue                                  -> {priority, cache, pending}
    class ApiHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            log.info("api %s - %s", self.address_string(), fmt % args)

        def _json(self, status: int, body: dict) -> None:
            payload = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_POST(self):
            if self.path != "/enqueue":
                self.send_error(404); return
            length = int(self.headers.get("Content-Length") or 0)
            if length <= 0 or length > 4096:
                self.send_error(400, "missing or oversized body"); return
            try:
                body = json.loads(self.rfile.read(length))
                url = (body.get("url") or "").strip()
                title = (body.get("title") or "").strip() or None
                if not (url.startswith("http://") or url.startswith("https://")):
                    raise ValueError("url must be http(s)")
            except Exception as e:
                self.send_error(400, str(e)); return
            item = submission_to_item(url, title)
            submission_queue.put(item)
            self._json(202, {"queued": True, "slug": item_slug(item["id"])})

        def do_GET(self):
            if self.path != "/queue":
                self.send_error(404); return
            self._json(200, {
                "priority": [p.name for p in sorted(PRIORITY_DIR.glob("*.mp4"))],
                "cache":    [p.name for p in sorted(CACHE_DIR.glob("*.mp4"))],
                "pending":  submission_queue.qsize(),
            })

    class ApiServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
        daemon_threads = True
        allow_reuse_address = True

    def api_loop() -> None:
        srv = ApiServer(("127.0.0.1", API_PORT), ApiHandler)
        log.info("api listening on 127.0.0.1:%d", API_PORT)
        try:
            srv.serve_forever(poll_interval=0.5)
        finally:
            srv.server_close()

    # ── Main ──────────────────────────────────────────────────────────────────
    def handle_signal(signum, _frame):
        log.info("signal %s — shutting down", signum)
        shutdown.set()
        with proc_lock:
            if current_remuxer and current_remuxer.poll() is None:
                current_remuxer.terminate()
            if current_master and current_master.poll() is None:
                try: current_master.stdin.close()
                except OSError: pass
                current_master.terminate()

    def main() -> int:
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s %(levelname)s %(message)s",
            stream=sys.stdout,
        )
        for d in (CACHE_DIR, PRIORITY_DIR, HLS_DIR, STATE_DIR, RUNTIME_DIR):
            d.mkdir(parents=True, exist_ok=True)
        load_state()
        ensure_filler()
        ensure_player_html()

        signal.signal(signal.SIGTERM, handle_signal)
        signal.signal(signal.SIGINT, handle_signal)

        threads = [
            threading.Thread(target=downloader_loop,   name="downloader",  daemon=True),
            threading.Thread(target=playout_loop,      name="playout",     daemon=True),
            threading.Thread(target=submission_worker, name="submissions", daemon=True),
            threading.Thread(target=api_loop,          name="api",         daemon=True),
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
    "d ${priorityDir}   0755 radio-video radio-video -"
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
  #
  # 5. Submit a clip to the priority queue (plays before any LoC item):
  #      curl -s -X POST http://127.0.0.1:${toString apiListenPort}/enqueue \
  #        -H 'Content-Type: application/json' \
  #        -d '{"url":"https://example.com/clip.mp4","title":"my clip"}'
  #      curl -s http://127.0.0.1:${toString apiListenPort}/queue | jq
  #    For remote submissions, add a Pangolin route to 127.0.0.1:${toString apiListenPort}
  #    behind whatever auth you want (the orchestrator itself does no auth —
  #    binding to loopback is the only access control).
}
