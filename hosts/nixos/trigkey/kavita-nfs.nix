{ ... }:

{
  # ── NFS export of Kavita's book folder, for Chaptarr on gmktec ───────────────
  # Export: /srv/kavita/books/books/chaptarr → gmktec (192.168.0.51) only
  # Port: 2049/tcp, NFSv4 only, scoped to gmktec by the nftables rule below
  #
  # Chaptarr (hosts/nixos/gmktec/chaptarr.nix) runs next to SABnzbd and
  # Prowlarr on gmktec and mounts this folder as its ebook root folder. Each
  # imported book is written straight into Kavita's "Books" library, which reads
  # /books/books inside the Kavita container (hosts/nixos/optional/kavita.nix).
  # Kavita's folder watching sees the new files, because nfsd writes through
  # this machine's own filesystem.
  #
  # Backed up — /srv/kavita is in the restic job in ./backup.nix.
  #
  # It lives in trigkey/ and not in ../optional/, because it is tied to this
  # machine's storage and to one client address.
  #
  # all_squash maps every client UID to eric:users (1000:100), the owner of
  # the rest of /srv/kavita/books/books. Chaptarr's container user on gmktec
  # has no account here, and Kavita runs as root, so it reads the files either
  # way. The export is the only subtree gmktec can write to.

  services.nfs.server = {
    enable = true;
    exports = ''
      /srv/kavita/books/books/chaptarr 192.168.0.51(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=100)
    '';
  };

  # NFSv4 needs only 2049, so v3 (and the rpcbind/mountd/statd ports it would
  # need open) stays off.
  services.nfs.settings.nfsd = {
    vers3 = false;
    "vers4.0" = false;
    "vers4.1" = true;
    "vers4.2" = true;
  };

  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.51 tcp dport 2049 accept comment "nfs kavita books to gmktec chaptarr"
  '';

  systemd.tmpfiles.rules = [
    "d /srv/kavita/books/books/chaptarr 0755 eric users -"
  ];
}
