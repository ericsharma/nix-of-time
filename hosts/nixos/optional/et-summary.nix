{ config, ... }:

{
  # ── E.T. read-aloud summaries ────────────────────────────────────────────────
  # Holding the speaker in the E.T. iOS app summarizes Claude's last reply. E.T.
  # runs curl on this host (the tmux server), and when no endpoint is set in the
  # app it reads /run/secrets/rendered/et-summary.env:
  #   ET_SUMMARY_URL  OpenAI-compatible chat endpoint: m1-mini's llama-server
  #                   (chat :8223, qwen3.5-9b), on the LAN at 192.168.0.5
  #   ET_SUMMARY_KEY  its Bearer key, the same m1-mini secret nam-shub uses
  #                   (encrypted to trigkey, see .sops.yaml), so one copy to rotate
  #   ET_TTS_URL      OpenAI-compatible speech endpoint: m1-mini's Kokoro
  #                   (kokoro-tts.nix, :8225), same key. Without it E.T. falls
  #                   back to the phone's own voice.
  # eric reads it because E.T. connects as eric.
  sops.secrets."et-summary/llm-api-key" = {
    sopsFile = ../../../secrets/m1-mini/llama-server.yaml;
    key = "llama-server/api-key";
  };
  sops.templates."et-summary.env" = {
    owner = "eric";
    mode = "0400";
    content = ''
      ET_SUMMARY_URL=http://192.168.0.5:8223/v1/chat/completions
      ET_SUMMARY_KEY=${config.sops.placeholder."et-summary/llm-api-key"}
      ET_TTS_URL=http://192.168.0.5:8225/v1/audio/speech
    '';
  };
}
