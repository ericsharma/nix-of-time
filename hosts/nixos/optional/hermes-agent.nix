{ hermes-agent, ... }:

# Nous Research's Hermes Agent (https://hermes-agent.nousresearch.com).
# Upstream ships a flake with a fully-baked NixOS module — we just import
# it and turn it on. Two pieces of native infrastructure to know about:
#
#   - State lives at /var/lib/hermes/.hermes (HERMES_HOME). The module
#     creates it 2770 hermes:hermes with the setgid bit, so members of
#     the hermes group share sessions, skills, memory, and cron with the
#     gateway service.
#   - The gateway runs as a systemd unit (`systemctl status hermes-agent`)
#     and binds nothing — all messaging happens outbound to provider APIs.
#
# Provider/model is intentionally unconfigured. Run `hermes model` once
# as eric to pick a provider; pinning it in Nix is optional and only
# worthwhile once we add an API key in sops (see TODO below).

{
  imports = [ hermes-agent.nixosModules.default ];

  services.hermes-agent = {
    enable = true;

    # Put `hermes` on the system PATH and export HERMES_HOME globally so
    # interactive shells share state with the gateway service instead of
    # creating a parallel ~/.hermes.
    addToSystemPackages = true;

    # Pin Grok 4.3 via xAI OAuth. Credentials live at
    # /var/lib/hermes/.hermes/auth.json (bootstrapped once with
    # `hermes auth add xai-oauth`) and refresh in place. The module's
    # config-merge script makes these Nix keys win on every activation
    # while preserving any user-added keys (skills, streaming, etc.).
    settings.model = {
      default = "grok-4.3";
      provider = "xai-oauth";
      base_url = "https://api.x.ai/v1";
    };

    # No messaging gateways wired in — CLI-only for now. Add Telegram /
    # Discord / Slack later by populating environmentFiles below with the
    # relevant bot tokens (see hermes-agent docs/user-guide/messaging).
    #
    # environmentFiles = [ config.sops.secrets."hermes/env".path ];
    #
    # And the matching sops block:
    #
    #   sops.secrets."hermes/env" = { owner = "hermes"; };
    #
    # With env-file contents like:
    #   ANTHROPIC_API_KEY=...
    #   OPENROUTER_API_KEY=...
    #   TELEGRAM_BOT_TOKEN=...
  };

  # Eric needs the hermes group to read/write the shared state directory.
  # Without this, `hermes` from eric's shell can launch but can't see the
  # service's sessions or write to its cron/memory dirs.
  users.users.eric.extraGroups = [ "hermes" ];

  # The setgid bit on HERMES_HOME makes new files inherit group=hermes, but
  # the service's default umask (0077) still strips group rw — so eric can't
  # take auth.lock or read auth.json despite being in the group. 0007 keeps
  # the world bits off while leaving group rw, which is what the shared-
  # group model actually needs.
  systemd.services.hermes-agent.serviceConfig.UMask = "0007";
}
