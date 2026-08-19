{ ... }:

{
  # ── Shared media root for the Usenet stack ───────────────────────────────────
  # Data path: /data (internal NVMe, ext4, ~900 GB free)
  # NOT backed up — every file here is re-downloadable from Usenet, and
  # /mnt/backup is reserved for trigkey's restic repository.
  #
  # One filesystem, one directory tree, one group. SABnzbd writes into
  # /data/usenet, and a later Sonarr/Radarr must see the *same absolute paths*
  # so it can hardlink the finished download into the library instead of copying
  # it. A hardlink cannot cross a filesystem boundary, so nothing here may move
  # to a second disk, and no service may get its own private bind mount.
  #
  #   /data/usenet/incomplete   SABnzbd work area (unpack, repair)
  #   /data/usenet/complete/*   finished downloads, one dir per category
  #   /data/media/{tv,movies}   the library Sonarr/Radarr will hardlink into
  #
  # Mode 2775: the setgid bit makes every new file and directory inherit the
  # `media` group, so services that run as different users still read and write
  # each other's output. Each service adds itself to `media` and sets
  # UMask = 0002.

  users.groups.media = { };

  systemd.tmpfiles.rules = [
    "d /data 0755 root root -"
    "d /data/usenet 2775 root media -"
    "d /data/usenet/incomplete 2775 root media -"
    "d /data/usenet/complete 2775 root media -"
    "d /data/media 2775 root media -"
    "d /data/media/tv 2775 root media -"
    "d /data/media/movies 2775 root media -"
  ];
}
