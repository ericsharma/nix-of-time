{
  config,
  lib,
  pkgs,
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

  audioStreamUrl = "http://127.0.0.1:8000/stream";
  hlsListenPort = 8088;
  apiListenPort = 8089; # enqueue API, 127.0.0.1 only — expose via Pangolin if remote
  cacheTarget = 3; # how many normalised mp4s to keep ready PER channel

  stateDir = "/var/lib/radio-video";
  cacheRoot = "${stateDir}/cache"; # per-channel subdirs: cache/<ch>/*.mp4
  priorityDir = "${stateDir}/priority"; # main-only, user-submitted clips, FIFO
  hlsRoot = "${stateDir}/hls"; # per-channel subdirs: hls/<ch>/stream.m3u8
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
      #ch-toggle { position: fixed; top: 0.75rem; right: 0.75rem;
                   width: 2rem; height: 2rem; border-radius: 50%;
                   background: rgba(255,255,255,0.08); color: #fff;
                   display: flex; align-items: center; justify-content: center;
                   font-size: 1.1rem; cursor: pointer; user-select: none;
                   opacity: 0.35; transition: opacity 0.2s;
                   border: 1px solid rgba(255,255,255,0.15); }
      #ch-toggle:hover { opacity: 1; }
      #ch-list { position: fixed; top: 3.25rem; right: 0.75rem;
                 background: rgba(20,20,20,0.92); color: #fff;
                 border: 1px solid rgba(255,255,255,0.15); border-radius: 0.5rem;
                 padding: 0.25rem 0; min-width: 10rem; display: none;
                 box-shadow: 0 4px 16px rgba(0,0,0,0.5); }
      #ch-list.open { display: block; }
      #ch-list .item { padding: 0.5rem 1rem; cursor: pointer; font-size: 0.9rem; }
      #ch-list .item:hover { background: rgba(255,255,255,0.08); }
      #ch-list .item.active { color: #6cf; }
    </style>
    </head>
    <body>
    <video id="v" autoplay muted playsinline controls></video>
    <div id="hint">tap / click anywhere for audio</div>
    <div id="ch-toggle" title="switch channel">≡</div>
    <div id="ch-list"></div>
    <script src="https://cdn.jsdelivr.net/npm/hls.js@1"></script>
    <script>
      // Channel list baked at build time from the nix `allChannels` value.
      var CHANNELS = ${builtins.toJSON (map (c: c.name) allChannels)};
      var DEFAULT_CHANNEL = ${builtins.toJSON mainChannelName};

      (function () {
        var v = document.getElementById('v');
        var hint = document.getElementById('hint');
        var toggle = document.getElementById('ch-toggle');
        var list = document.getElementById('ch-list');
        var hls = null;

        function currentChannel() {
          var h = (window.location.hash || "").replace(/^#/, "");
          return CHANNELS.indexOf(h) >= 0 ? h : DEFAULT_CHANNEL;
        }

        function renderList(active) {
          list.innerHTML = "";
          CHANNELS.forEach(function (name) {
            var el = document.createElement("div");
            el.className = "item" + (name === active ? " active" : "");
            el.textContent = name;
            el.addEventListener("click", function () {
              window.location.hash = "#" + name;
              list.classList.remove("open");
            });
            list.appendChild(el);
          });
        }

        function load(channel) {
          var src = "/" + channel + "/stream.m3u8";
          renderList(channel);
          if (hls) { try { hls.destroy(); } catch (_) {} hls = null; }
          if (window.Hls && Hls.isSupported()) {
            hls = new Hls({
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
        }

        toggle.addEventListener('click', function (e) {
          e.stopPropagation();
          list.classList.toggle('open');
        });
        document.body.addEventListener('click', function () {
          list.classList.remove('open');
        });
        window.addEventListener('hashchange', function () { load(currentChannel()); });

        function unmute() {
          v.muted = false;
          v.play().catch(function () {});
          hint.classList.add('gone');
          document.body.removeEventListener('click', unmuteWrap);
          document.body.removeEventListener('touchstart', unmuteWrap);
        }
        // Wrapped to coexist with the body click-closes-list handler.
        function unmuteWrap(e) { if (e.target !== toggle) unmute(); }
        document.body.addEventListener('click', unmuteWrap);
        document.body.addEventListener('touchstart', unmuteWrap);

        load(currentChannel());
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
    CACHE_ROOT   = Path("${cacheRoot}")
    PRIORITY_DIR = Path("${priorityDir}")
    HLS_ROOT     = Path("${hlsRoot}")
    STATE_DIR    = Path("${stateDir}")
    RUNTIME_DIR  = Path("${runtimeDir}")
    FILLER_PATH  = Path("${fillerPath}")
    STATE_FILE   = STATE_DIR / "state.json"
    AUDIO_URL    = "${audioStreamUrl}"
    API_PORT     = ${toString apiListenPort}
    CHANNELS     = ${builtins.toJSON allChannels}
    MAIN_NAME    = "${mainChannelName}"
    CACHE_TARGET = ${toString cacheTarget}
    HISTORY_MAX  = 500
    # How often to re-fetch a non-main channel's collection listing from LoC.
    ITEMS_TTL    = 24 * 3600

    def ch_cache(ch: dict) -> Path:    return CACHE_ROOT / ch["name"]
    def ch_hls(ch: dict)   -> Path:    return HLS_ROOT / ch["name"]
    def is_main(ch: dict)  -> bool:    return ch["name"] == MAIN_NAME
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
    # Shape: {"channels": {<name>: {"history": [...], "seg_num": N,
    #                               "items": [...], "items_refreshed": ts,
    #                               "index": N}}}
    # Only `main` uses history. Non-main channels use items+index for the
    # sequential walk. seg_num is per-channel so master-ffmpeg restarts on
    # one channel can't collide with another's segment numbering.
    state_lock = threading.Lock()
    state: dict = {"channels": {}}

    def _default_ch_state() -> dict:
        return {"history": [], "seg_num": 1000,
                "items": [], "items_refreshed": 0, "index": 0}

    def load_state() -> None:
        global state
        if STATE_FILE.exists():
            try:
                state = json.loads(STATE_FILE.read_text())
            except Exception as e:
                log.warning("could not load state: %s", e)
        # Migrate legacy flat shape -> nested channels.main.
        if "history" in state or "seg_num" in state:
            legacy = {"history": state.pop("history", []),
                      "seg_num": state.pop("seg_num", 1000)}
            chs = state.setdefault("channels", {})
            main = chs.setdefault(MAIN_NAME, _default_ch_state())
            main["history"] = legacy["history"]
            main["seg_num"] = legacy["seg_num"]
            log.info("migrated legacy state to channels.%s", MAIN_NAME)
        chs = state.setdefault("channels", {})
        for ch in CHANNELS:
            slot = chs.setdefault(ch["name"], _default_ch_state())
            for k, v in _default_ch_state().items():
                slot.setdefault(k, v)

    def save_state() -> None:
        tmp = STATE_FILE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(state))
        tmp.replace(STATE_FILE)

    def ch_state(name: str) -> dict:
        return state["channels"].setdefault(name, _default_ch_state())

    def remember(channel: str, item_id: str) -> None:
        with state_lock:
            h = ch_state(channel)["history"]
            if item_id in h:
                h.remove(item_id)
            h.append(item_id)
            del h[:-HISTORY_MAX]
            save_state()

    def seen(channel: str, item_id: str) -> bool:
        with state_lock:
            return item_id in ch_state(channel)["history"]

    def reserve_seg_nums(channel: str, count: int) -> int:
        # Per-channel monotonic counter so segment filenames never collide
        # across master-ffmpeg restarts on the same channel.
        with state_lock:
            slot = ch_state(channel)
            n = slot["seg_num"]
            slot["seg_num"] = n + count
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
    def _result_to_item(item: dict) -> dict | None:
        iid = item.get("id") or item.get("url")
        if not iid:
            return None
        # Search results carry the direct mp4 URL on resources[0].video; no
        # item-detail fetch needed.
        res_list = item.get("resources") or []
        video_url = (res_list[0].get("video") if res_list else None)
        if not video_url:
            return None
        return {"id": iid,
                "url": item.get("url") or iid,
                "title": item.get("title", ""),
                "video_url": video_url}

    def pick_main_item(allow_seen: bool = False) -> dict | None:
        """Random pick across main's collections, respecting main's history."""
        main_cols = next((c["collections"] for c in CHANNELS
                          if c["name"] == MAIN_NAME), [])
        if not main_cols:
            log.error("main channel has no collections — check radio-video.nix")
            return None
        cols = list(main_cols)
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
                log.warning("pick_main %s failed: %s", col, e)
                continue
            random.shuffle(results)
            for raw in results:
                item = _result_to_item(raw)
                if not item:
                    continue
                if not allow_seen and seen(MAIN_NAME, item["id"]):
                    continue
                return item
        return None

    def fetch_collection_items(collection: str) -> list[dict]:
        """Walk every page of a collection, return all items with a video_url."""
        items: list[dict] = []
        page = 1
        while True:
            try:
                base = f"https://www.loc.gov/{collection}/"
                params = {"fo": "json", "fa": "original-format:film,+video",
                          "c": "100", "sp": str(page)}
                resp = http_get_json(base + "?" + urllib.parse.urlencode(params, safe=",+"))
            except Exception as e:
                log.warning("fetch_collection %s page=%d: %s", collection, page, e)
                break
            results = resp.get("results") or []
            if not results:
                break
            for raw in results:
                item = _result_to_item(raw)
                if item:
                    items.append(item)
            pagination = resp.get("pagination") or {}
            total = int(pagination.get("total") or 1) or 1
            if page >= total:
                break
            page += 1
        log.info("fetched %d items from %s", len(items), collection)
        return items

    def pick_sequential_item(ch: dict) -> dict | None:
        """Next item in a non-main channel: walk the collection in order, loop."""
        name = ch["name"]
        with state_lock:
            slot = ch_state(name)
            stale = (not slot["items"]
                     or time.time() - slot.get("items_refreshed", 0) > ITEMS_TTL)
        if stale:
            all_items: list[dict] = []
            for col in ch["collections"]:
                all_items.extend(fetch_collection_items(col))
            if not all_items:
                log.warning("channel %s: no items in any collection", name)
                return None
            # Stable order by id so the sequential walk is deterministic across
            # restarts. (LoC's pagination order isn't promised stable.)
            all_items.sort(key=lambda i: i["id"])
            with state_lock:
                slot = ch_state(name)
                slot["items"] = all_items
                slot["items_refreshed"] = int(time.time())
                slot["index"] = slot.get("index", 0) % len(all_items)
                save_state()
        with state_lock:
            slot = ch_state(name)
            items = slot["items"]
            if not items:
                return None
            idx = slot["index"] % len(items)
            slot["index"] = (idx + 1) % len(items)
            save_state()
            return items[idx]

    # ── Download + normalize ──────────────────────────────────────────────────
    def item_slug(item_id: str) -> str:
        # LoC item ids look like "http://www.loc.gov/item/00694018/" — keep
        # the final path component (e.g. "00694018"). Sanitised for FS safety.
        last = item_id.rstrip("/").rsplit("/", 1)[-1] or "item"
        return re.sub(r"[^A-Za-z0-9._-]", "_", last)[:80]

    # Serialises every downloader + the user-submission worker so they don't
    # fight for bandwidth or hammer ffmpeg in parallel. Per-channel parallelism
    # would amplify load without helping the bottleneck (one network pipe).
    download_lock = threading.Lock()

    def download_and_normalize(item: dict, target_dir: Path,
                                remember_in: str | None = None) -> Path | None:
        """Download + normalize a clip into `target_dir`. If `remember_in` is
        set, push the item id into that channel's history.

        Critical invariant: never let a partial mp4 appear in `target_dir`. The
        playout loop globs that dir and will pick up any *.mp4 it finds, even
        if ffmpeg's `+faststart` pass hasn't relocated the moov atom yet. We
        therefore stage the normalized output in `raw/` (same filesystem) and
        atomic-rename into `target_dir` only after ffmpeg fully exits.
        """
        slug = item_slug(item["id"])
        raw_dir = STATE_DIR / "raw"
        raw_dir.mkdir(parents=True, exist_ok=True)
        raw = raw_dir / f"{slug}.mp4"
        staged = raw_dir / f"{slug}.normalized.mp4"
        for p in (raw, staged):
            if p.exists():
                try: p.unlink()
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
                    str(staged),
                ], check=True, timeout=3600)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                log.warning("normalize failed for %s: %s", raw, e)
                if staged.exists():
                    try: staged.unlink()
                    except OSError: pass
                return None
            finally:
                try: raw.unlink()
                except OSError: pass

        out = target_dir / f"{slug}.mp4"
        try:
            staged.replace(out)  # atomic on same filesystem
        except OSError as e:
            log.warning("could not finalize %s -> %s: %s", staged, out, e)
            if staged.exists():
                try: staged.unlink()
                except OSError: pass
            return None

        if remember_in is not None:
            remember(remember_in, item["id"])
        log.info("ready[%s/%s]: %s (%s)",
                 target_dir.parent.name, target_dir.name,
                 out.name, item.get("title", ""))
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
        # User submissions land in main's priority dir; they bypass history so
        # the same URL can be re-submitted and re-played at will.
        while not shutdown.is_set():
            try:
                item = submission_queue.get(timeout=1.0)
            except queue.Empty:
                continue
            try:
                log.info("submission: %s (%s)", item["title"], item["video_url"])
                download_and_normalize(item, target_dir=PRIORITY_DIR, remember_in=None)
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
        # Player lives at the HLS root; per-channel manifests live in
        # /<channel>/stream.m3u8 below it. The page reads the current channel
        # from window.location.hash and falls back to MAIN_NAME.
        target = HLS_ROOT / "index.html"
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
    # ONE long-running "master" ffmpeg per channel writes that channel's HLS
    # manifest. It reads an mpegts video stream from stdin (fed by Python from
    # sequential per-clip remuxers) plus the icecast audio. Because the master
    # never exits, the manifest is appended to continuously across clip
    # boundaries — no restart gap, no PTS reset, no DISCONTINUITY marker.
    #
    # Per-clip remuxers stream-copy each normalised mp4 into mpegts with
    # `-output_ts_offset` set to the running play-time, so successive clips
    # produce a single monotonic PTS timeline.
    shutdown = threading.Event()

    def build_master_cmd(ch: dict, start_num: int) -> list[str]:
        hls_dir = ch_hls(ch)
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
            "-hls_segment_filename", str(hls_dir / "seg-%05d.ts"),
            "-start_number", str(start_num),
            str(hls_dir / "stream.m3u8"),
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

    def start_master(ch: dict) -> subprocess.Popen:
        # Reserve a big block of segment numbers per master invocation so
        # any prior segments lingering on disk can't collide with new ones.
        start_num = reserve_seg_nums(ch["name"], 100_000)
        log.info("[%s] starting master ffmpeg (start_number=%d)",
                 ch["name"], start_num)
        return subprocess.Popen(
            build_master_cmd(ch, start_num),
            stdin=subprocess.PIPE,
            bufsize=0,
        )

    def pick_next_clip(ch: dict) -> Path:
        # main: priority dir (user submissions, FIFO) > cache dir > filler.
        # Non-main channels have no priority dir.
        if is_main(ch):
            pri = sorted(PRIORITY_DIR.glob("*.mp4"))
            if pri:
                return pri[0]
        cands = sorted(ch_cache(ch).glob("*.mp4"))
        return cands[0] if cands else FILLER_PATH

    def feed_clip(ch: dict, master: subprocess.Popen,
                  clip: Path, ts_offset: float) -> float:
        """Pipe one clip's mpegts into the master. Returns clip duration on success."""
        duration = probe_duration(clip)
        log.info("[%s] feeding %s (%.1fs, offset=%.1fs)",
                 ch["name"], clip.name, duration, ts_offset)
        remuxer = subprocess.Popen(
            build_remuxer_cmd(clip, ts_offset),
            stdout=subprocess.PIPE,
            bufsize=0,
        )
        try:
            while True:
                chunk = remuxer.stdout.read(65536)
                if not chunk:
                    break
                try:
                    master.stdin.write(chunk)
                    master.stdin.flush()
                except (BrokenPipeError, OSError):
                    log.warning("[%s] master pipe broken while feeding %s",
                                ch["name"], clip.name)
                    if remuxer.poll() is None:
                        remuxer.terminate()
                    raise
        finally:
            try:
                remuxer.stdout.close()
            except OSError:
                pass
            remuxer.wait()
        return duration

    def playout_loop(ch: dict) -> None:
        backoff = 1.0
        while not shutdown.is_set():
            try:
                master = start_master(ch)
                ts_offset = 0.0
                while not shutdown.is_set() and master.poll() is None:
                    clip = pick_next_clip(ch)
                    try:
                        played = feed_clip(ch, master, clip, ts_offset)
                    except (BrokenPipeError, OSError):
                        # master died mid-feed; outer loop will respawn
                        break
                    ts_offset += played
                    # Delete the played clip only if it lives in this channel's
                    # cache or main's priority dir. Filler is shared/eternal.
                    if clip != FILLER_PATH and clip.exists():
                        try: clip.unlink()
                        except OSError: pass
                    backoff = 1.0
                if master.poll() is None:
                    try: master.stdin.close()
                    except OSError: pass
                    master.terminate()
                rc = master.wait()
                if not shutdown.is_set():
                    log.warning("[%s] master ffmpeg exited rc=%s, restarting",
                                ch["name"], rc)
                    shutdown.wait(backoff)
                    backoff = min(backoff * 2, 30.0)
            except Exception as e:
                log.exception("[%s] playout: %s", ch["name"], e)
                shutdown.wait(2)

    # ── Downloader thread ─────────────────────────────────────────────────────
    def downloader_loop(ch: dict) -> None:
        target = ch_cache(ch)
        while not shutdown.is_set():
            try:
                ready = list(target.glob("*.mp4"))
                if len(ready) >= CACHE_TARGET:
                    shutdown.wait(15)
                    continue
                if is_main(ch):
                    item = pick_main_item()
                    if not item:
                        # LoC unreachable or every result on the random page is
                        # in `seen`. Retry allowing seen items so we don't get
                        # stranded in filler-loop forever.
                        item = pick_main_item(allow_seen=True)
                        if item:
                            log.info("[%s] history exhausted — replaying %s",
                                     ch["name"], item.get("title", item["id"]))
                    if not item:
                        shutdown.wait(30)
                        continue
                    download_and_normalize(item, target_dir=target,
                                            remember_in=MAIN_NAME)
                else:
                    item = pick_sequential_item(ch)
                    if not item:
                        shutdown.wait(30)
                        continue
                    download_and_normalize(item, target_dir=target,
                                            remember_in=None)
            except Exception as e:
                log.exception("[%s] downloader: %s", ch["name"], e)
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
            if self.path == "/channels":
                self._json(200, {"channels": [c["name"] for c in CHANNELS],
                                  "main": MAIN_NAME})
                return
            if self.path != "/queue":
                self.send_error(404); return
            self._json(200, {
                "priority": [p.name for p in sorted(PRIORITY_DIR.glob("*.mp4"))],
                "caches": {ch["name"]: [p.name for p in sorted(ch_cache(ch).glob("*.mp4"))]
                           for ch in CHANNELS},
                "pending": submission_queue.qsize(),
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
        # daemon threads + systemd's process-group kill handle the rest.

    def main() -> int:
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s %(levelname)s %(message)s",
            stream=sys.stdout,
        )
        for d in (CACHE_ROOT, PRIORITY_DIR, HLS_ROOT, STATE_DIR, RUNTIME_DIR):
            d.mkdir(parents=True, exist_ok=True)
        for ch in CHANNELS:
            ch_cache(ch).mkdir(parents=True, exist_ok=True)
            ch_hls(ch).mkdir(parents=True, exist_ok=True)
        load_state()
        ensure_filler()
        ensure_player_html()

        signal.signal(signal.SIGTERM, handle_signal)
        signal.signal(signal.SIGINT, handle_signal)

        threads: list[threading.Thread] = []
        for ch in CHANNELS:
            threads.append(threading.Thread(
                target=downloader_loop, args=(ch,),
                name=f"dl-{ch['name']}", daemon=True))
            threads.append(threading.Thread(
                target=playout_loop, args=(ch,),
                name=f"pl-{ch['name']}", daemon=True))
        threads.append(threading.Thread(
            target=submission_worker, name="submissions", daemon=True))
        threads.append(threading.Thread(
            target=api_loop, name="api", daemon=True))
        for t in threads:
            t.start()

        sd_notify("READY=1")
        log.info("ready: %d channels (%s)", len(CHANNELS),
                 ", ".join(c["name"] for c in CHANNELS))

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
    "d ${cacheRoot}     0755 radio-video radio-video -"
    "d ${priorityDir}   0755 radio-video radio-video -"
    "d ${hlsRoot}       0755 radio-video radio-video -"
    "d ${stateDir}/raw  0755 radio-video radio-video -"
    "d ${runtimeDir}    0755 radio-video radio-video -"
  ]
  ++ lib.concatMap (ch: [
    "d ${cacheRoot}/${ch.name}  0755 radio-video radio-video -"
    "d ${hlsRoot}/${ch.name}    0755 radio-video radio-video -"
  ]) allChannels;

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
      root = hlsRoot;
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
}
