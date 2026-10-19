{ config, pkgs, ... }:

let
  # Prints a current access token for Hermes's xAI sign-in (the SuperGrok
  # subscription, see hermes-agent.nix), refreshing it first if it is about to
  # expire. It calls Hermes's own resolve function rather than reading
  # auth.json: xAI rotates the refresh token on every refresh, and Hermes saves
  # the new one under its auth lock. A refresh done any other way would leave
  # Hermes holding a dead refresh token and force `hermes auth add xai-oauth`.
  #
  # Runs as eric (E.T.'s login), exactly like `hermes` from eric's shell, so a
  # refresh here leaves auth.json the same as an interactive refresh would.
  # umask 0007 matches the gateway's UMask for anything else it creates.
  etGrokToken = pkgs.writeShellScriptBin "et-grok-token" ''
    umask 0007
    export HERMES_HOME=/var/lib/hermes/.hermes
    exec ${config.services.hermes-agent.package.passthru.hermesVenv}/bin/python3 -c \
      'from hermes_cli.auth import resolve_xai_oauth_runtime_credentials as r; print(r()["api_key"])'
  '';
in
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
  #   ET_GROK_*       the "Grok" summary model in E.T.: xAI's API with the
  #                   token from et-grok-token (ET_GROK_KEY_CMD) instead of a
  #                   stored key. ET_GROK_MODEL is any model `hermes model`
  #                   lists for xai-oauth.
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
      ET_GROK_URL=https://api.x.ai/v1/chat/completions
      ET_GROK_MODEL=grok-4.3
      ET_GROK_KEY_CMD=${etGrokToken}/bin/et-grok-token
    '';
  };

  environment.systemPackages = [ etGrokToken ];
}
