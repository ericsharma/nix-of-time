# Audio transcription

Drop an audio file into a vault's `Transcriptions/` folder in Obsidian. A markdown transcript with speaker labels and an inline audio player syncs back next to it.

| Vault | Watched folder on trigkey |
|-------|---------------------------|
| Work | `/srv/obsidian/Work/Transcriptions/` |
| Brain 2.0 | `/srv/obsidian/Brain 2.0/Transcriptions/` |

## How it works

1. [Syncthing](syncthing.md) copies the file to trigkey.
2. A systemd service running `inotifywait` sees it.
3. `podman run` starts WhisperX (`ghcr.io/jim60105/whisperx:no_model`, CPU, INT8) for that one file.
4. The transcript (an `![[audio.m4a]]` embed, timestamps, speaker labels) is written beside the audio.
5. Syncthing copies the transcript back.

- Module: `hosts/nixos/optional/whisper-transcription.nix`
- Speaker diarization uses a Hugging Face token from sops, loaded as an `EnvironmentFile`.
- Only audio files (`m4a`, `mp3`, `wav`, `ogg`, `flac`, …) are processed, and only if no transcript exists yet.
