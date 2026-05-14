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

  # ── Static HLS player page ─────────────────────────────────────────────────
  # The page is a self-contained static file (HTML + inline CSS/JS) that
  # discovers channels at runtime via /api/channels and submits to /api/enqueue.
  # Keeping it out of a Nix `''` block avoids escaping the JS-heavy source.
  playerHtml = pkgs.writeText "radio-video-player.html"
    (builtins.readFile ./radio-video-player.html);

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
    import shutil
    import signal
    import socket
    import socketserver
    import subprocess
    import sys
    import tempfile
    import threading
    import time
    import urllib.parse
    from pathlib import Path

    # ── Config (Nix-interpolated) ──────────────────────────────────────────────
    CACHE_ROOT     = Path("${cacheRoot}")
    PRIORITY_DIR   = Path("${priorityDir}")
    HLS_ROOT       = Path("${hlsRoot}")
    CAPTURES_DIR   = Path("${capturesDir}")
    USER_CLIPS_DIR = Path("${userClipsDir}")
    STATE_DIR      = Path("${stateDir}")
    RUNTIME_DIR   = Path("${runtimeDir}")
    AUDIO_BUF_DIR = Path("${audioBufferDir}")
    FILLER_PATH   = Path("${fillerPath}")
    STATE_FILE    = STATE_DIR / "state.json"
    API_PORT      = ${toString apiListenPort}
    CHANNELS      = ${builtins.toJSON allChannels}
    AUDIO_SOURCES = ${builtins.toJSON audioSources}
    DEFAULT_AUDIO = "${defaultAudio}"
    MAIN_NAME     = "${mainChannelName}"
    CACHE_TARGET  = ${toString cacheTarget}
    HLS_LIST_SIZE = ${toString hlsListSize}
    CAPTURE_MAX_S = ${toString captureMaxSeconds}
    AUDIO_SEG_S   = ${toString audioSegSeconds}
    AUDIO_SEG_WRAP = ${toString audioSegWrap}
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
        # Grab a generous set of LoC metadata fields. Coverage varies item-to-
        # item; we keep what's present and let the frontend choose what to
        # render. Lists are passed through; single-value fields are coerced.
        def _first(v):
            if isinstance(v, list):
                return v[0] if v else None
            return v
        return {
            "id": iid,
            "url": item.get("url") or iid,
            "title": item.get("title", ""),
            "video_url": video_url,
            "date": _first(item.get("date") or item.get("dates")) or "",
            "contributors": item.get("contributor_names")
                            or item.get("contributors") or [],
            "subjects": item.get("subject") or [],
            "description": _first(item.get("description")) or "",
            "partof": item.get("partof") or item.get("partof_title") or [],
            "original_format": item.get("original_format") or [],
            "language": item.get("language") or [],
            "kind": "loc",
        }

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
        sidecar = out.with_suffix(".json")

        # Write the sidecar BEFORE the .mp4 lands. The playout loop globs
        # *.mp4 and will happily pick this clip up the instant it appears,
        # which would race a later sidecar write and leave us with no
        # now-playing metadata for the clip.
        sidecar_payload = dict(item)
        sidecar_payload["ready_at"] = int(time.time())
        try:
            tmp_sc = sidecar.with_suffix(".json.tmp")
            tmp_sc.write_text(json.dumps(sidecar_payload))
            tmp_sc.replace(sidecar)
        except OSError as e:
            log.warning("could not write sidecar %s: %s", sidecar, e)

        try:
            staged.replace(out)  # atomic on same filesystem
        except OSError as e:
            log.warning("could not finalize %s -> %s: %s", staged, out, e)
            if staged.exists():
                try: staged.unlink()
                except OSError: pass
            if sidecar.exists():
                try: sidecar.unlink()
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

    # Bounded ring of recent submission outcomes, surfaced via /queue so the
    # frontend can show "your last submission failed because …" instead of
    # the user staring at an empty queue panel.
    submission_results: list = []
    results_lock = threading.Lock()

    def record_result(item: dict, status: str, message: str = "",
                       resolved_url: str | None = None) -> None:
        entry = {
            "url": item.get("url") or item.get("video_url") or "",
            "title": item.get("title") or item.get("url") or "",
            "status": status,         # "queued" | "resolving" | "downloading" | "ready" | "failed"
            "message": message,
            "resolved_url": resolved_url,
            "at": int(time.time()),
            "slug": item_slug(item.get("id") or ""),
        }
        with results_lock:
            # Replace the latest entry for the same slug, otherwise prepend.
            for i, e in enumerate(submission_results):
                if e["slug"] == entry["slug"]:
                    submission_results[i] = entry
                    return
            submission_results.insert(0, entry)
            del submission_results[20:]

    def submission_to_item(url: str, title: str | None,
                             audio_id: str | None = None) -> dict:
        ts_ms = int(time.time() * 1000)
        short = hashlib.sha1(url.encode()).hexdigest()[:8]
        pseudo_id = f"{ts_ms:013d}-{short}"
        # audio_id is stamped on the submission so the archive baker can
        # later bake whatever radio source the user had on screen when they
        # clicked Submit — even if playout happens minutes later.
        sid = audio_id if audio_id in AUDIO_SOURCES_BY_ID else DEFAULT_AUDIO
        return {"id": pseudo_id, "url": url,
                "title": title or url, "video_url": url,
                "kind": "submission",
                "audio_id": sid}

    # User-pasted URLs are almost always the LoC item or archive.org details
    # page, not a direct video file. Resolve them to a downloadable mp4 here
    # so the modal's "paste a LoC URL" promise actually holds.
    _DIRECT_VIDEO_EXTS = re.compile(r"\.(mp4|m4v|webm|mov|mkv|ogv|ogg|avi|ts)(\?|$)", re.I)
    _LOC_ITEM_RE     = re.compile(r"^https?://(?:www\.)?loc\.gov/(item|resource)/([^/?#]+)", re.I)
    _ARCHIVE_PAGE_RE = re.compile(r"^https?://archive\.org/(?:details|embed)/([^/?#]+)", re.I)
    _ARCHIVE_DL_RE   = re.compile(r"^https?://archive\.org/download/", re.I)

    def _loc_resolve(kind: str, ident: str) -> str | None:
        url = f"https://www.loc.gov/{kind}/{ident}/?fo=json"
        try:
            data = http_get_json(url)
        except Exception as e:
            log.warning("resolve LoC %s/%s: %s", kind, ident, e)
            return None
        # LoC item-detail responses put media under several possible keys.
        # 1) `item.resources[*].video` (same shape as search results)
        for res in (data.get("resources") or []):
            v = res.get("video")
            if isinstance(v, str) and v:
                return v
            # 2) `item.resources[*].files[*][*]` — each leaf file is a dict
            #    with a `url` and `mimetype`/`format`.
            for f_outer in (res.get("files") or []):
                files = f_outer if isinstance(f_outer, list) else [f_outer]
                for f in files:
                    if not isinstance(f, dict):
                        continue
                    fu = f.get("url") or ""
                    mt = (f.get("mimetype") or "").lower()
                    if fu and (_DIRECT_VIDEO_EXTS.search(fu) or mt.startswith("video/")):
                        return fu
        return None

    def _archive_resolve(ident: str) -> str | None:
        try:
            meta = http_get_json(f"https://archive.org/metadata/{ident}")
        except Exception as e:
            log.warning("resolve archive.org %s: %s", ident, e)
            return None
        files = meta.get("files") or []
        # Prefer h.264 mp4 derivatives; archive.org typically ships a 512kb
        # derivative alongside the master, which is fine for our use.
        def score(f: dict) -> int:
            name = (f.get("name") or "").lower()
            fmt  = (f.get("format") or "").lower()
            s = 0
            if name.endswith(".mp4"):                     s += 5
            if "h.264" in fmt or "mpeg4" in fmt:          s += 3
            if "512kb" in name or "ia.mp4" in name:       s += 2
            if "thumb" in name or "sample" in name:       s -= 5
            return -s  # python sort ascending; we want highest score first
        candidates = [f for f in files if isinstance(f, dict) and f.get("name")]
        candidates.sort(key=score)
        for f in candidates:
            name = f.get("name") or ""
            if name.lower().endswith(".mp4"):
                return f"https://archive.org/download/{ident}/{name}"
        return None

    def resolve_video_url(url: str) -> str | None:
        """Best-effort: turn a user-pasted URL into a direct video URL.
        Returns None if no video could be located."""
        if not url:
            return None
        # Already a direct video file (or archive.org/download/ which always is).
        if _DIRECT_VIDEO_EXTS.search(url) or _ARCHIVE_DL_RE.match(url):
            return url
        m = _LOC_ITEM_RE.match(url)
        if m:
            return _loc_resolve(m.group(1), m.group(2))
        m = _ARCHIVE_PAGE_RE.match(url)
        if m:
            return _archive_resolve(m.group(1))
        # Unknown shape — let the user shoot themselves in the foot if they
        # really did paste something exotic. download_and_normalize will fail
        # gracefully and record_result will surface that to the UI.
        return url

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
                # Single `processing` covers resolve + download + normalise;
                # the user can't usefully distinguish them. Terminal states
                # are `played` (set by feed_clip) and `failed`.
                record_result(item, "processing")
                resolved = resolve_video_url(item["video_url"])
                if not resolved:
                    log.warning("submission: could not resolve %s", item["video_url"])
                    record_result(item, "failed",
                                  "no direct video URL found at that page "
                                  "(paste an LoC item URL, an archive.org "
                                  "details page, or a direct .mp4 link)")
                    continue
                if resolved != item["video_url"]:
                    log.info("submission: resolved %s -> %s",
                             item["video_url"], resolved)
                item = dict(item, video_url=resolved)
                out = download_and_normalize(item, target_dir=PRIORITY_DIR,
                                              remember_in=None)
                if not out:
                    record_result(item, "failed",
                                  "download or normalize failed — see "
                                  "`journalctl -u radio-video-orchestrator`",
                                  resolved_url=resolved)
                    continue
                # Archive a copy for the user. Hardlink (same FS) so we don't
                # double disk usage; when the playout FIFO unlinks the priority
                # mp4 after playback, the FS refcount keeps the data alive at
                # /user-clips/<slug>.mp4 until tmpfiles cleans it up (7d).
                archive_url = stash_user_clip(out)
                if archive_url:
                    with results_lock:
                        for entry in submission_results:
                            if entry.get("slug") == item_slug(item["id"]):
                                entry["archive_url"] = archive_url
                                break
            except Exception as e:
                log.exception("submission failed: %s", e)
                record_result(item, "failed", str(e))

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

    # ── Now-playing tracking ─────────────────────────────────────────────────
    # Updated by feed_clip() when a clip starts; read by the /now endpoint.
    # Per-channel dict — `None` while filler is on air or before first clip.
    now_lock = threading.Lock()
    now_playing: dict = {ch["name"]: None for ch in CHANNELS}

    def set_now(channel: str, info: dict | None) -> None:
        with now_lock:
            now_playing[channel] = info

    def read_sidecar(clip: Path) -> dict | None:
        """Best-effort read of the .json sidecar next to a cached clip."""
        sc = clip.with_suffix(".json")
        if not sc.exists():
            return None
        try:
            return json.loads(sc.read_text())
        except (OSError, ValueError) as e:
            log.warning("could not read sidecar %s: %s", sc, e)
            return None

    # ── Audio metadata ────────────────────────────────────────────────────────
    # The browser plays its own <audio> element; this section just publishes
    # current-track metadata for each source so the HUD chyron stays
    # informative regardless of which one the user picked.
    #
    #   icecast → /status-json.xsl on loopback (liquidsoap publishes the
    #             current track title there)
    #   nts     → https://www.nts.live/api/v2/live (single JSON for both
    #             NTS 1 and NTS 2 — cached together)
    AUDIO_SOURCES_BY_ID = {s["id"]: s for s in AUDIO_SOURCES}

    ICECAST_STATUS_URL = "http://127.0.0.1:8000/status-json.xsl"
    NTS_LIVE_URL       = "https://www.nts.live/api/v2/live"

    _audio_lock = threading.Lock()
    # Keyed by audio_id for icecast; "nts" shares one cache across channels.
    _audio_cache: dict = {}  # {key: {"ts": float, "data": dict|None}}

    def _cache_get(key: str, ttl: float) -> tuple[bool, dict | None]:
        with _audio_lock:
            slot = _audio_cache.get(key)
            if slot and time.time() - slot["ts"] < ttl:
                return True, slot["data"]
        return False, None

    def _cache_put(key: str, data: dict | None) -> None:
        with _audio_lock:
            _audio_cache[key] = {"ts": time.time(), "data": data}

    def _fetch_icecast(source: dict) -> dict | None:
        try:
            out = subprocess.check_output(
                ["curl", "-sfL", "--max-time", "3", ICECAST_STATUS_URL],
                timeout=5,
            )
            parsed = json.loads(out)
        except (subprocess.CalledProcessError,
                subprocess.TimeoutExpired,
                ValueError) as e:
            log.debug("icecast status fetch failed: %s", e)
            return None
        src = (parsed.get("icestats") or {}).get("source")
        if isinstance(src, list):
            src = next((s for s in src
                        if isinstance(s, dict)
                        and (s.get("listenurl") or "").endswith("/stream")),
                       src[0] if src else None)
        if not isinstance(src, dict):
            return None
        return {
            "source_id": source["id"],
            "source_label": source["label"],
            "kind": "icecast",
            "title": (src.get("title")
                      or src.get("yp_currently_playing") or ""),
            "artist": src.get("artist") or "",
            "name": src.get("server_name") or "",
            "description": src.get("server_description") or "",
            "listeners": src.get("listeners") or 0,
            "bitrate": src.get("bitrate"),
            "genre": src.get("genre") or "",
        }

    def _fetch_nts_raw() -> dict | None:
        # One API call covers both NTS 1 and NTS 2; cache the full payload
        # under "nts" and let the per-source helper pick its channel out.
        try:
            out = subprocess.check_output(
                ["curl", "-sfL", "--max-time", "5",
                 "-A", HTTP_UA,
                 "-H", "Accept: application/json",
                 NTS_LIVE_URL],
                timeout=8,
            )
            return json.loads(out)
        except (subprocess.CalledProcessError,
                subprocess.TimeoutExpired,
                ValueError) as e:
            log.debug("nts live fetch failed: %s", e)
            return None

    def _fetch_nts(source: dict) -> dict | None:
        # 15s TTL: the NTS API is a public CDN-cached endpoint and shows
        # change on the order of half-hours, so polling more often is wasteful.
        hit, cached = _cache_get("nts:raw", 15.0)
        raw = cached if hit else _fetch_nts_raw()
        if not hit:
            _cache_put("nts:raw", raw)
        if not raw:
            return None
        target = str(source.get("ntsChannel") or "")
        results = raw.get("results") or []
        chan = next((c for c in results
                     if isinstance(c, dict)
                     and str(c.get("channel_name") or "") == target),
                    None)
        if not chan:
            return None
        now = chan.get("now") or {}
        details = ((now.get("embeds") or {}).get("details")) or {}
        genres = [g.get("value") for g in (details.get("genres") or [])
                  if isinstance(g, dict) and g.get("value")]
        # NTS's "broadcast_title" is e.g. "FLOATING POINTS - 010825"; the
        # nested `details.name` is the cleaner show name without the date.
        title = details.get("name") or now.get("broadcast_title") or ""
        # `description` is HTML-ish; trim to one line for the chyron.
        desc = (details.get("description") or "").strip().split("\n", 1)[0]
        return {
            "source_id": source["id"],
            "source_label": source["label"],
            "kind": "nts",
            "title": title,
            "artist": "",  # NTS doesn't expose per-track artist
            "name": source["label"],
            "description": desc,
            "listeners": None,
            "bitrate": None,
            "genre": ", ".join(genres[:3]),
            "starts": now.get("start_timestamp") or "",
            "ends":   now.get("end_timestamp")   or "",
        }

    # ── Audio taps: rolling per-source buffer for /api/capture ────────────────
    # One ffmpeg per source pulls the live stream and writes a small ring of
    # AAC-in-mpegts segments. Capture muxes the most recent N into the captured
    # video so users get the radio audio they were listening to.
    def start_audio_tap(source: dict) -> subprocess.Popen:
        sid = source["id"]
        buf = AUDIO_BUF_DIR / sid
        buf.mkdir(parents=True, exist_ok=True)
        # Let stderr inherit so ffmpeg errors land in `journalctl -u
        # radio-video-orchestrator` — taps fail silently otherwise.
        return subprocess.Popen([
            "ffmpeg", "-nostdin", "-loglevel", "warning",
            "-reconnect", "1", "-reconnect_streamed", "1",
            "-reconnect_delay_max", "5",
            "-user_agent", HTTP_UA,
            "-i", source["serverUrl"],
            "-vn",
            "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "2",
            "-f", "segment",
            "-segment_time", str(AUDIO_SEG_S),
            "-segment_wrap", str(AUDIO_SEG_WRAP),
            "-segment_format", "mpegts",
            "-reset_timestamps", "1",
            str(buf / "seg-%05d.ts"),
        ], stdout=subprocess.DEVNULL)

    def audio_tap_loop(source: dict) -> None:
        sid = source["id"]
        backoff = 2.0
        while not shutdown.is_set():
            try:
                proc = start_audio_tap(source)
                started_at = time.monotonic()
                log.info("audio tap[%s] started (pid=%d)", sid, proc.pid)
                while not shutdown.is_set() and proc.poll() is None:
                    shutdown.wait(2)
                if shutdown.is_set():
                    if proc.poll() is None:
                        proc.terminate()
                        try: proc.wait(timeout=5)
                        except subprocess.TimeoutExpired: proc.kill()
                    return
                # Reset backoff if the tap ran long enough to be considered
                # healthy — otherwise a once-stable source that dies after
                # hours would stay stuck at the 30s ceiling.
                if time.monotonic() - started_at > 60:
                    backoff = 2.0
                log.warning("audio tap[%s] exited rc=%s, restarting in %.1fs",
                            sid, proc.returncode, backoff)
                shutdown.wait(backoff)
                backoff = min(backoff * 2, 30.0)
            except Exception as e:
                log.exception("audio tap[%s]: %s", sid, e)
                shutdown.wait(5)

    def fetch_audio_now(audio_id: str | None = None) -> dict | None:
        """Resolve current-track metadata for an audio source id (or default)."""
        sid = audio_id if audio_id in AUDIO_SOURCES_BY_ID else DEFAULT_AUDIO
        source = AUDIO_SOURCES_BY_ID.get(sid)
        if not source:
            return None
        kind = source.get("kind")
        # Icecast: per-id cache (only one icecast right now, but cheap to scope).
        # NTS: the helper does its own shared-cache lookup on "nts:raw".
        if kind == "icecast":
            hit, cached = _cache_get(f"src:{sid}", 3.0)
            if hit:
                return cached
            info = _fetch_icecast(source)
            _cache_put(f"src:{sid}", info)
            return info
        if kind == "nts":
            return _fetch_nts(source)
        return None

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
        # Video-only HLS; audio is overlaid in the browser via a parallel
        # <audio> element so the user can switch stations.
        hls_dir = ch_hls(ch)
        return [
            "ffmpeg", "-nostdin", "-loglevel", "warning",
            "-fflags", "+genpts+discardcorrupt",
            "-f", "mpegts", "-i", "pipe:0",
            "-map", "0:v:0",
            "-c:v", "copy",
            "-f", "hls",
            "-hls_time", "4",
            "-hls_list_size", str(HLS_LIST_SIZE),
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

        # Publish now-playing metadata for the /now endpoint. Sidecar wins;
        # filler/sidecar-less clips get a synthetic entry.
        if clip == FILLER_PATH:
            info = {"kind": "filler", "title": "filler",
                    "description": "between transmissions"}
        else:
            info = read_sidecar(clip) or {
                "kind": "unknown", "title": clip.stem,
            }
        info = dict(info)
        info["started_at"] = int(time.time())
        info["duration_s"] = round(duration, 2)
        info["channel"] = ch["name"]
        set_now(ch["name"], info)

        # If this is a user submission, flip the submission_results entry to
        # "played" so the frontend can show "✓ played 5m ago for Ns on main"
        # instead of the clip silently disappearing once the FIFO consumes it.
        if info.get("kind") == "submission":
            slug = item_slug(info.get("id") or "")
            with results_lock:
                for entry in submission_results:
                    if entry.get("slug") == slug:
                        entry["status"] = "played"
                        entry["played_at"] = info["started_at"]
                        entry["duration_s"] = info["duration_s"]
                        entry["channel"] = ch["name"]
                        break

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
                    # For user submissions, bake the radio audio that was
                    # selected at submit time into the archived (silent) copy
                    # in parallel with playout.
                    bake_proc: subprocess.Popen | None = None
                    if clip.parent == PRIORITY_DIR:
                        bake_proc = start_archive_baker(clip, probe_duration(clip))
                    try:
                        played = feed_clip(ch, master, clip, ts_offset)
                    except (BrokenPipeError, OSError):
                        if bake_proc and bake_proc.poll() is None:
                            bake_proc.terminate()
                        # master died mid-feed; outer loop will respawn
                        break
                    ts_offset += played
                    if bake_proc is not None:
                        threading.Thread(
                            target=finalize_archive_bake,
                            args=(bake_proc, clip),
                            name=f"bake-{clip.stem}",
                            daemon=True,
                        ).start()
                    # Delete the played clip only if it lives in this channel's
                    # cache or main's priority dir. Filler is shared/eternal.
                    # (Bake fd, if any, keeps the inode alive past unlink.)
                    if clip != FILLER_PATH and clip.exists():
                        try: clip.unlink()
                        except OSError: pass
                        sidecar = clip.with_suffix(".json")
                        if sidecar.exists():
                            try: sidecar.unlink()
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

    # ── Instant-replay capture ────────────────────────────────────────────────
    # Concat the most recent N seconds of a channel's on-disk HLS segments
    # into a single mp4 with `-c copy` (no re-encode). The HLS master is
    # constantly writing new segments and (because of delete_segments) pruning
    # old ones, so we hardlink the segments we want into a temp dir first;
    # the hardlink keeps the data alive even if the master unlinks the
    # original right after our glob.
    def list_segments(channel: str) -> list[Path]:
        return sorted((HLS_ROOT / channel).glob("seg-*.ts"),
                      key=lambda p: p.stat().st_mtime)

    def snapshot_segments(chosen: list[Path], tmp: Path, *,
                           copy: bool, prefix: str = "") -> list[Path]:
        """Snapshot segments into `tmp` so the source ring can keep rotating
        beneath us. Use copy=False for hardlinks (same FS), copy=True for
        shutil.copyfile (cross-FS — tmpfs audio buffer → disk-backed tmp dir
        fails EXDEV otherwise)."""
        out: list[Path] = []
        for s in chosen:
            d = tmp / (prefix + s.name)
            try:
                if copy:
                    shutil.copyfile(s, d)
                else:
                    os.link(s, d)
            except (FileNotFoundError, OSError) as e:
                log.debug("snapshot %s: %s", s.name, e)
                continue
            out.append(d)
        return out

    def pick_audio_segments(audio_id: str, seconds: int,
                             tmp: Path) -> list[Path]:
        buf = AUDIO_BUF_DIR / audio_id
        if not buf.is_dir():
            return []
        all_segs = sorted(buf.glob("seg-*.ts"),
                          key=lambda p: p.stat().st_mtime)
        # Drop the newest segment — ffmpeg is actively writing it, copying it
        # mid-write yields a truncated tail in the capture.
        if len(all_segs) < 2:
            return []
        finalized = all_segs[:-1]
        # +2 segments so ffmpeg can drop the first partial one cleanly.
        need = (seconds + AUDIO_SEG_S - 1) // AUDIO_SEG_S + 2
        return snapshot_segments(finalized[-need:], tmp,
                                  copy=True, prefix="audio-")

    def capture_channel(channel: str, seconds: int,
                         audio_id: str | None = None) -> Path | None:
        seconds = max(5, min(int(seconds), CAPTURE_MAX_S))
        # HLS segments are ~4s each; grab a couple extra so `-t` has enough
        # material to trim from after a keyframe.
        seg_target = (seconds + 3) // 4 + 2
        segs = list_segments(channel)
        if not segs:
            log.warning("capture[%s]: no segments on disk yet", channel)
            return None
        chosen = segs[-seg_target:]

        tmp = Path(tempfile.mkdtemp(prefix="capture-", dir=STATE_DIR / "raw"))
        try:
            linked = snapshot_segments(chosen, tmp, copy=False)
            if not linked:
                log.warning("capture[%s]: nothing left after race with master ffmpeg",
                            channel)
                return None

            audio_linked = (pick_audio_segments(audio_id, seconds, tmp)
                            if audio_id else [])

            ts_ms = int(time.time() * 1000)
            out = CAPTURES_DIR / f"{channel}-{ts_ms}-{seconds}s.mp4"
            vid_concat = "concat:" + "|".join(str(p) for p in linked)
            cmd = ["ffmpeg", "-y", "-nostdin", "-loglevel", "error",
                   "-i", vid_concat]
            if audio_linked:
                aud_concat = "concat:" + "|".join(str(p) for p in audio_linked)
                cmd += ["-i", aud_concat,
                        "-map", "0:v:0", "-map", "1:a:0",
                        "-c:v", "copy",
                        "-c:a", "aac", "-b:a", "128k",
                        "-shortest"]
            else:
                cmd += ["-c", "copy"]
            cmd += ["-t", str(seconds),
                    "-movflags", "+faststart",
                    str(out)]
            try:
                subprocess.run(cmd, check=True, timeout=120)
            except (subprocess.CalledProcessError,
                    subprocess.TimeoutExpired) as e:
                log.warning("capture[%s]: ffmpeg failed: %s", channel, e)
                if out.exists():
                    try: out.unlink()
                    except OSError: pass
                return None
            log.info("capture[%s]: %s (%d s, %d vid + %d aud segs%s)",
                     channel, out.name, seconds, len(linked),
                     len(audio_linked), f" from {audio_id}" if audio_id else "")
            return out
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    # ── Archive of user-submitted clips ──────────────────────────────────────
    # A successful submission's normalised mp4 is hardlinked here right after
    # `download_and_normalize` returns. The hardlink (same FS as priority/)
    # is free, and the FS refcount survives the FIFO unlink that happens
    # after playback — so users can still retrieve their clip later.
    def stash_user_clip(src: Path) -> str | None:
        dst = USER_CLIPS_DIR / src.name
        try:
            if dst.exists():
                dst.unlink()
            os.link(src, dst)
        except OSError as e:
            log.warning("stash %s: %s", src.name, e)
            return None
        # Sidecar JSON too, so the listing has metadata.
        sc_src = src.with_suffix(".json")
        sc_dst = dst.with_suffix(".json")
        if sc_src.exists():
            try:
                if sc_dst.exists():
                    sc_dst.unlink()
                os.link(sc_src, sc_dst)
            except OSError as e:
                log.warning("stash sidecar %s: %s", sc_src.name, e)
        log.info("stashed user clip %s", dst.name)
        return f"/user-clips/{dst.name}"

    # The normalised priority mp4 is silent (normalize strips audio, the HLS
    # master is video-only). The baker reads the user's chosen `audio_id`
    # from the sidecar so the mixed-down archive matches what aired.
    def start_archive_baker(clip: Path,
                             duration: float) -> subprocess.Popen | None:
        if clip.parent != PRIORITY_DIR:
            return None
        target = USER_CLIPS_DIR / clip.name
        if not target.exists():
            return None
        sidecar = read_sidecar(clip) or {}
        sid = sidecar.get("audio_id") or DEFAULT_AUDIO
        source = AUDIO_SOURCES_BY_ID.get(sid) or AUDIO_SOURCES_BY_ID.get(DEFAULT_AUDIO)
        if not source:
            log.warning("archive baker: no audio source for %s (sid=%s)",
                        clip.name, sid)
            return None
        audio_url = source["serverUrl"]
        out_tmp = USER_CLIPS_DIR / f".{clip.stem}.bake.mp4"
        if out_tmp.exists():
            try: out_tmp.unlink()
            except OSError: pass
        try:
            return subprocess.Popen([
                "ffmpeg", "-y", "-nostdin", "-loglevel", "error",
                "-re", "-i", str(clip),
                "-re", "-i", audio_url,
                "-map", "0:v:0", "-map", "1:a:0",
                "-c:v", "copy",
                "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "2",
                "-shortest",
                "-t", f"{duration + 1.5:.3f}",
                "-movflags", "+faststart",
                str(out_tmp),
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError as e:
            log.warning("archive baker: spawn failed for %s: %s", clip.name, e)
            return None

    def finalize_archive_bake(proc: subprocess.Popen, clip: Path) -> None:
        """Wait for the baker to finish, then atomically replace the silent
        user-clip with the audio-mixed version. Runs in a background thread
        so it doesn't hold up the playout loop."""
        target = USER_CLIPS_DIR / clip.name
        out_tmp = USER_CLIPS_DIR / f".{clip.stem}.bake.mp4"
        try:
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.terminate()
                try: proc.wait(timeout=5)
                except subprocess.TimeoutExpired: proc.kill()
            if proc.returncode == 0 and out_tmp.exists() and target.exists():
                try:
                    os.replace(out_tmp, target)
                    log.info("baked radio audio into %s", target.name)
                except OSError as e:
                    log.warning("bake replace failed for %s: %s", target.name, e)
            else:
                log.warning("bake exit=%s for %s — keeping silent archive",
                            proc.returncode, target.name)
        finally:
            if out_tmp.exists():
                try: out_tmp.unlink()
                except OSError: pass

    def _list_mp4_dir(directory: Path, build_entry) -> list[dict]:
        out = []
        for p in sorted(directory.glob("*.mp4"),
                        key=lambda p: p.stat().st_mtime, reverse=True):
            try:
                st = p.stat()
            except OSError:
                continue
            out.append(build_entry(p, st))
        return out[:20]

    def list_user_clips() -> list[dict]:
        def build(p: Path, st) -> dict:
            info = read_sidecar(p) or {}
            return {
                "filename": p.name,
                "url": f"/user-clips/{p.name}",
                "title": info.get("title") or p.stem,
                "source_url": info.get("url") or info.get("video_url") or "",
                "size_bytes": st.st_size,
                "saved_at": int(st.st_mtime),
            }
        return _list_mp4_dir(USER_CLIPS_DIR, build)

    def list_captures() -> list[dict]:
        def build(p: Path, st) -> dict:
            # filename: <channel>-<ms>-<N>s.mp4
            m = re.match(r"^(.*)-(\d+)-(\d+)s\.mp4$", p.name)
            return {
                "filename": p.name,
                "url": f"/captures/{p.name}",
                "channel": m.group(1) if m else "",
                "seconds": int(m.group(3)) if m else 0,
                "size_bytes": st.st_size,
                "captured_at": int(st.st_mtime),
            }
        return _list_mp4_dir(CAPTURES_DIR, build)

    # ── HTTP API ──────────────────────────────────────────────────────────────
    # Bound to 127.0.0.1; expose via a Pangolin route if remote access is wanted.
    # Endpoints:
    #   POST /enqueue {"url": "...", "title": "?"}  -> 202 {queued, slug}
    #   POST /capture {"channel": "...", "seconds": N} -> 200 {url, filename, ...}
    #   GET  /queue                                  -> {priority, caches, pending,
    #                                                    submissions, captures, now}
    #   GET  /captures                               -> {captures: [...]}
    #   GET  /channels                               -> {channels, main}
    #   GET  /audio-sources                          -> {sources: [...], default}
    #   GET  /now?audio=<id>                         -> {video: {<ch>: ...}, audio: {...}}
    #   GET  /queue?audio=<id>                       -> (same shape as before; audio metadata reflects ?audio)
    def _parse_query(path: str) -> tuple[str, dict]:
        # Cheap split — urllib.parse.urlsplit handles weird inputs but we only
        # need /path?key=val from same-origin requests.
        parts = urllib.parse.urlsplit(path)
        qs = {k: (v[0] if v else "")
              for k, v in urllib.parse.parse_qs(parts.query).items()}
        return parts.path, qs

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

        def _read_json(self, max_bytes: int = 4096) -> dict:
            length = int(self.headers.get("Content-Length") or 0)
            if length <= 0 or length > max_bytes:
                raise ValueError("missing or oversized body")
            return json.loads(self.rfile.read(length))

        def do_POST(self):
            path, _ = _parse_query(self.path)
            if path == "/enqueue":
                try:
                    body = self._read_json()
                    url = (body.get("url") or "").strip()
                    title = (body.get("title") or "").strip() or None
                    audio = (body.get("audio") or "").strip() or None
                    if not (url.startswith("http://") or url.startswith("https://")):
                        raise ValueError("url must be http(s)")
                except Exception as e:
                    self.send_error(400, str(e)); return
                item = submission_to_item(url, title, audio_id=audio)
                submission_queue.put(item)
                self._json(202, {"queued": True, "slug": item_slug(item["id"])})
                return
            if path == "/capture":
                try:
                    body = self._read_json()
                    channel = (body.get("channel") or MAIN_NAME).strip()
                    seconds = int(body.get("seconds") or 30)
                    audio = (body.get("audio") or "").strip() or None
                except Exception as e:
                    self.send_error(400, str(e)); return
                if channel not in {c["name"] for c in CHANNELS}:
                    self.send_error(400, "unknown channel"); return
                if audio and audio not in AUDIO_SOURCES_BY_ID:
                    audio = None
                out = capture_channel(channel, seconds, audio_id=audio)
                if not out:
                    self.send_error(503,
                        "no segments to capture yet — try again in a few seconds")
                    return
                st = out.stat()
                self._json(200, {
                    "filename": out.name,
                    "url": f"/captures/{out.name}",
                    "channel": channel,
                    "seconds": min(max(seconds, 5), CAPTURE_MAX_S),
                    "size_bytes": st.st_size,
                    "captured_at": int(st.st_mtime),
                })
                return
            self.send_error(404)

        def do_GET(self):
            path, qs = _parse_query(self.path)
            audio_id = qs.get("audio") or DEFAULT_AUDIO
            if path == "/channels":
                self._json(200, {"channels": [c["name"] for c in CHANNELS],
                                  "main": MAIN_NAME})
                return
            if path == "/audio-sources":
                # Only publicUrl is exposed; serverUrl is loopback-only.
                self._json(200, {
                    "sources": [{"id": s["id"], "label": s["label"],
                                  "url": s["publicUrl"], "kind": s["kind"]}
                                 for s in AUDIO_SOURCES],
                    "default": DEFAULT_AUDIO,
                })
                return
            if path == "/now":
                with now_lock:
                    snap = {k: v for k, v in now_playing.items()}
                self._json(200, {"video": snap,
                                  "audio": fetch_audio_now(audio_id),
                                  "audio_id": audio_id})
                return
            if path == "/captures":
                self._json(200, {"captures": list_captures()})
                return
            if path == "/clips":
                self._json(200, {"clips": list_user_clips()})
                return
            if path != "/queue":
                self.send_error(404); return
            with now_lock:
                snap = {k: v for k, v in now_playing.items()}
            with results_lock:
                recent = list(submission_results)
            self._json(200, {
                "priority": [p.name for p in sorted(PRIORITY_DIR.glob("*.mp4"))],
                "caches": {ch["name"]: [p.name for p in sorted(ch_cache(ch).glob("*.mp4"))]
                           for ch in CHANNELS},
                "pending": submission_queue.qsize(),
                "submissions": recent,
                "captures": list_captures(),
                "user_clips": list_user_clips(),
                "now": {"video": snap,
                         "audio": fetch_audio_now(audio_id),
                         "audio_id": audio_id},
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
        for d in (CACHE_ROOT, PRIORITY_DIR, HLS_ROOT, CAPTURES_DIR,
                  USER_CLIPS_DIR, STATE_DIR, RUNTIME_DIR, AUDIO_BUF_DIR):
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
        for src in AUDIO_SOURCES:
            threads.append(threading.Thread(
                target=audio_tap_loop, args=(src,),
                name=f"tap-{src['id']}", daemon=True))
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
  # The captures dir gets a `7d` age field — systemd-tmpfiles-clean.timer
  # (daily) prunes files older than 7 days so user-recorded clips don't pile
  # up indefinitely.
  systemd.tmpfiles.rules = [
    "d ${stateDir}      0755 radio-video radio-video -"
    "d ${cacheRoot}     0755 radio-video radio-video -"
    "d ${priorityDir}   0755 radio-video radio-video -"
    "d ${hlsRoot}       0755 radio-video radio-video -"
    "d ${capturesDir}   0755 radio-video radio-video 7d"
    "d ${userClipsDir}  0755 radio-video radio-video 7d"
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
    # icecast is only ONE of the audio sources users can pick (the others are
    # NTS streams reachable directly from the browser), and the HLS master
    # no longer mixes audio at all — so a brief icecast outage is no longer
    # a reason to refuse to start. Keep `after` for ordering when both run.
    wants = [
      "network-online.target"
      "icecast.service"
    ];
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
