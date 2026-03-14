{ config, pkgs, ... }:

let
  image = "ghcr.io/jim60105/whisperx:no_model";

  # Audio file extensions to process (everything else is ignored)
  audioExts = "m4a|mp3|wav|ogg|flac|webm|mp4|aac|wma";

  # Vault Transcriptions directories watched by inotifywait
  vaultDirs = [
    "/srv/obsidian/Work/Transcriptions"
    "/srv/obsidian/Brain 2.0/Transcriptions"
  ];

  # ── Processing script ──────────────────────────────────────────────────────
  # Called by the watcher for each new audio file.
  # Runs whisperx via Podman, formats diarized output as Obsidian markdown
  # with an embedded audio player, placed alongside the audio in the vault.
  process-audio = pkgs.writeShellScript "whisper-process-audio" ''
    set -euo pipefail

    WORK_DIR="/srv/transcription/work"

    FILE="$1"
    VAULT_DIR="$(dirname "$FILE")"
    BASENAME="$(basename "$FILE")"
    STEM="''${BASENAME%.*}"
    EXT="''${BASENAME##*.}"

    # Skip non-audio files
    if ! echo "$EXT" | grep -qiE '^(${audioExts})$'; then
      exit 0
    fi

    # Skip if transcript already exists
    if [ -f "$VAULT_DIR/$STEM.md" ]; then
      echo "[whisper-transcription] Skipping $BASENAME — transcript already exists"
      exit 0
    fi

    echo "[whisper-transcription] Processing: $BASENAME → $VAULT_DIR"

    # Clean work dir
    rm -rf "$WORK_DIR"/*

    # ── Run whisperx in Podman ─────────────────────────────────────────────
    podman run --rm \
      -e "HF_TOKEN=$HF_TOKEN" \
      -v "$VAULT_DIR:/input:ro" \
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
    python3 - "$JSON" "$VAULT_DIR/$STEM.md" "$BASENAME" <<'PYEOF'
import json, sys, os
from datetime import datetime

json_path  = sys.argv[1]
md_path    = sys.argv[2]
audio_file = sys.argv[3]

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
    out.write(f"![[{audio_file}]]\n\n")
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

    echo "[whisper-transcription] Done: $BASENAME"
  '';

  # ── Watcher script ─────────────────────────────────────────────────────────
  # Watches the Transcriptions folder inside each Obsidian vault.
  # Audio files synced from a laptop via Syncthing trigger transcription.
  watch-audio = pkgs.writeShellScript "whisper-watch-audio" ''
    set -euo pipefail

    DIRS=(
    ${builtins.concatStringsSep "\n" (map (d: "  \"${d}\"") vaultDirs)}
    )

    echo "[whisper-transcription] Watching: ''${DIRS[*]}"

    # Process any audio files that arrived while the service was down
    for dir in "''${DIRS[@]}"; do
      for f in "$dir"/*; do
        [ -f "$f" ] && ${process-audio} "$f" || true
      done
    done

    # Watch for new files (close_write fires once Syncthing finishes writing)
    inotifywait \
      --monitor \
      --event close_write \
      --format '%w%f' \
      "''${DIRS[@]}" \
    | while read -r FILE; do
        ${process-audio} "$FILE" || echo "[whisper-transcription] ERROR processing $FILE" >&2
      done
  '';
in
{
  # ── Directories ──────────────────────────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d /srv/transcription      0755 eric users -"
    "d /srv/transcription/work 0755 eric users -"
    "d /srv/obsidian/Work/Transcriptions       0755 eric users -"
    "d /srv/obsidian/Brain 2.0/Transcriptions  0755 eric users -"
  ];

  # ── Systemd service ─────────────────────────────────────────────────────────
  systemd.services.whisper-transcription = {
    description = "Watched-folder audio transcription with WhisperX";
    after    = [ "network.target" "podman.service" "syncthing.service" ];
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
