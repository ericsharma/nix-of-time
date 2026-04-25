# Audio transcription

Automated watched-folder transcription using [WhisperX](https://github.com/m-bain/whisperX) (`hosts/optional/whisper-transcription.nix`). Integrated with Syncthing and Obsidian for a seamless end-to-end workflow.

## How it works

```
Laptop (Obsidian)                    Trigkey (headless)
┌────────────────────┐               ┌────────────────────────────┐
│ Drop audio into    │   Syncthing   │ inotifywait detects file   │
│ Transcriptions/    │──────────────►│ whisperx transcribes       │
│                    │               │ .md appears alongside audio│
│ Transcript + audio │◄──────────────│ Syncthing syncs back       │
│ appear in Obsidian │               │                            │
└────────────────────┘               └────────────────────────────┘
```

1. Drop an audio file into the `Transcriptions/` folder in your Obsidian vault
2. Syncthing syncs it to trigkey (`/srv/obsidian/<vault>/Transcriptions/`)
3. inotifywait triggers whisperx (CPU, INT8, speaker diarization)
4. A markdown transcript with an embedded audio player is written next to the audio file
5. Syncthing syncs the transcript back to your laptop
6. Open the transcript in Obsidian — play the audio inline while reading

## Details

- **Container** — `ghcr.io/jim60105/whisperx:no_model`, CPU-only (INT8), invoked per-file via `podman run`
- **Watcher** — systemd service using `inotifywait`, starts on boot
- **Diarization** — HuggingFace token loaded via sops `EnvironmentFile` for pyannote speaker models
- **Output** — Obsidian markdown with `![[audio.m4a]]` embed, timestamps, and speaker labels
- **Filtering** — only processes audio files (`m4a`, `mp3`, `wav`, `ogg`, `flac`, etc.), skips files that already have a matching transcript

## Watched directories

Two Obsidian vaults are watched, each with its own `Transcriptions/` folder:

```
/srv/obsidian/Work/Transcriptions/
/srv/obsidian/Brain 2.0/Transcriptions/
```

Drop audio into the `Transcriptions/` folder of whichever vault it belongs to.
