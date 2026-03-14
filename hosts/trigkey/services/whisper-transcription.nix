{ config, pkgs, ... }:

let
  image = "ghcr.io/jim60105/whisperx:no_model";

  # ── Processing script ──────────────────────────────────────────────────────
  # Called by the watcher for each new audio file.
  # Runs whisperx via Podman, formats diarized output as Obsidian markdown,
  # then archives the original audio.
  process-audio = pkgs.writeShellScript "whisper-process-audio" ''
    set -euo pipefail

    INPUT_DIR="/srv/transcription/input"
    OUTPUT_DIR="/srv/transcription/output"
    ARCHIVE_DIR="/srv/transcription/archive"
    WORK_DIR="/srv/transcription/work"

    FILE="$1"
    BASENAME="$(basename "$FILE")"
    STEM="''${BASENAME%.*}"

    echo "[whisper-transcription] Processing: $BASENAME"

    # Clean work dir
    rm -rf "$WORK_DIR"/*

    # ── Run whisperx in Podman ─────────────────────────────────────────────
    podman run --rm \
      -e "HF_TOKEN=$HF_TOKEN" \
      -v "$INPUT_DIR:/input:ro" \
      -v "$WORK_DIR:/output:U" \
      ${image} \
        -- \
        --model small \
        --compute_type int8 \
        --device cpu \
        --diarize \
        --output_dir /output \
        --output_format json \
        "/input/$BASENAME"

    JSON="$WORK_DIR/$STEM.json"

    if [ ! -f "$JSON" ]; then
      echo "[whisper-transcription] ERROR: whisperx produced no output for $BASENAME" >&2
      exit 1
    fi

    # ── Convert JSON → Obsidian-friendly Markdown ──────────────────────────
    python3 - "$JSON" "$OUTPUT_DIR/$STEM.md" <<'PYEOF'
import json, sys, os
from datetime import datetime

json_path = sys.argv[1]
md_path   = sys.argv[2]

with open(json_path) as f:
    data = json.load(f)

segments = data.get("segments", [])
basename = os.path.splitext(os.path.basename(json_path))[0]

def fmt_ts(seconds):
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    return f"{h:02d}:{m:02d}:{s:02d}"

with open(md_path, "w") as out:
    out.write(f"# {basename}\n\n")
    out.write(f"> Transcribed on {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\n")
    out.write("---\n\n")

    current_speaker = None
    for seg in segments:
        speaker = seg.get("speaker", "Unknown")
        start   = seg.get("start", 0)
        end     = seg.get("end", 0)
        text    = seg.get("text", "").strip()

        if not text:
            continue

        if speaker != current_speaker:
            current_speaker = speaker
            out.write(f"### {speaker}\n\n")

        out.write(f"**[{fmt_ts(start)} → {fmt_ts(end)}]** {text}\n\n")

print(f"[whisper-transcription] Wrote: {md_path}")
PYEOF

    # ── Archive the original audio file ────────────────────────────────────
    mv "$FILE" "$ARCHIVE_DIR/$BASENAME"
    echo "[whisper-transcription] Archived: $BASENAME"
  '';

  # ── Watcher script ─────────────────────────────────────────────────────────
  watch-audio = pkgs.writeShellScript "whisper-watch-audio" ''
    set -euo pipefail

    INPUT_DIR="/srv/transcription/input"

    echo "[whisper-transcription] Watching $INPUT_DIR for new audio files..."

    # Process any files that were dropped in while the service was down
    for f in "$INPUT_DIR"/*; do
      [ -f "$f" ] && ${process-audio} "$f" || true
    done

    # Watch for new files (close_write fires once the file is fully written)
    inotifywait \
      --monitor \
      --event close_write \
      --format '%w%f' \
      "$INPUT_DIR" \
    | while read -r FILE; do
        ${process-audio} "$FILE" || echo "[whisper-transcription] ERROR processing $FILE" >&2
      done
  '';
in
{
  # ── Directories ──────────────────────────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d /srv/transcription         0755 eric users -"
    "d /srv/transcription/input   0755 eric users -"
    "d /srv/transcription/output  0755 eric users -"
    "d /srv/transcription/archive 0755 eric users -"
    "d /srv/transcription/work    0755 eric users -"
  ];

  # ── Systemd service ─────────────────────────────────────────────────────────
  systemd.services.whisper-transcription = {
    description = "Watched-folder audio transcription with WhisperX";
    after    = [ "network.target" "podman.service" ];
    wantedBy = [ "multi-user.target" ];

    path = [
      config.virtualisation.podman.package
      pkgs.python3
      pkgs.inotify-tools
      pkgs.coreutils
    ];

    serviceConfig = {
      Type       = "simple";
      ExecStart  = watch-audio;
      Restart    = "on-failure";
      RestartSec = 10;

      # Run as eric — no need for root
      User  = "eric";
      Group = "users";

      # HuggingFace token for speaker diarization (pyannote models)
      # Content: HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxx
      EnvironmentFile = config.sops.secrets."whisper/env".path;
    };
  };

  # ── Secret: HuggingFace token env file ───────────────────────────────────────
  sops.secrets."whisper/env" = {
    owner = "eric";
  };
}
