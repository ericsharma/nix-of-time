{ ... }:

{
  # ── Inside Deutsche Bank explainer (static HTML) ────────────────────────────
  # Port: 4212 (localhost only; LAN name http://inside-db.local via portless)
  #
  # A one-page interactive explainer of the inside-db.com leak stories. The
  # page lives next to this module, so nginx serves it straight from the
  # /nix/store copy of ./inside-db. No build step; edit index.html and rebuild.
  services.nginx = {
    enable = true;
    virtualHosts."inside-db" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 4212;
        }
      ];
      root = ./inside-db;
      locations."/" = {
        tryFiles = "$uri $uri/ =404";
      };
    };
  };
}
