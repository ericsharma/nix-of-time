# Single source of truth for facts about the homelab that more than one
# module needs to agree on (currently host → IP, used by monitoring scrape
# targets). Pure data — no config, no logic. Pass via specialArgs.
{
  hosts = {
    trigkey = {
      address = "127.0.0.1";
    };
    docker-services = {
      address = "10.0.100.10";
    };
  };
}
