{ ... }:

{
  programs.tmux = {
    enable = true;

    # --- QUALITY OF LIFE ---
    # Windows and panes are 1-indexed, with auto-renumbering.
    baseIndex = 1;

    # --- MOUSE & TOUCH SUPPORT ---
    mouse = true;

    focusEvents = true;

    # Don't swallow the ESC key (fixes vim/nvim ESC lag)
    escapeTime = 10;

    # --- HISTORY ---
    historyLimit = 10000;

    extraConfig = ''
      # --- STATUS BAR ---
      # Every segment carries explicit fg AND bg. Never use `bg=default` for
      # window styles: inside the status line "default" resolves to the status
      # bar's own background, which is how you end up with cyan-on-green.
      set -g status-style "bg=#181825,fg=#a6adc8"

      set -g status-left-length 30
      set -g status-left "#[fg=#11111b,bg=#89b4fa,bold] #S #[fg=#89b4fa,bg=#181825,nobold] "

      set -g status-right-length 60
      set -g status-right "#[fg=#6c7086]#{=/20:pane_title} #[fg=#45475a]| #[fg=#11111b,bg=#89b4fa,bold] %H:%M "

      # Inactive windows: light grey on dark. Active: dark on red.
      set -g window-status-format         "#[fg=#a6adc8,bg=#181825] #I #W#{?window_flags,#{window_flags}, } "
      set -g window-status-current-format "#[fg=#11111b,bg=#f38ba8,bold] #I #W#{?window_flags,#{window_flags}, } "
      set -g window-status-separator ""

      set -g window-status-bell-style     "fg=#11111b,bg=#f9e2af,bold"
      set -g window-status-activity-style "fg=#f9e2af,bg=#181825"

      set -g pane-border-style        "fg=#313244"
      set -g pane-active-border-style "fg=#89b4fa"
      set -g message-style            "fg=#11111b,bg=#89b4fa,bold"

      # --- TERMINAL CAPABILITIES ---
      # Advertise truecolor + undercurl per-terminal rather than blanket-overriding,
      # since Terminal.app can't do RGB.
      set -as terminal-features ",xterm-ghostty:RGB:usstyle"
      set -as terminal-features ",xterm-256color:RGB:usstyle"

      # OSC 52: yanking in tmux lands in the local clipboard, even over ssh
      set -g set-clipboard on

      # --- EASIER SPLITTING ---
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window -c "#{pane_current_path}"

      bind r source-file ~/.config/tmux/tmux.conf \; display-message "tmux.conf reloaded"

      # --- QUALITY OF LIFE ---
      set -g renumber-windows on
    '';
  };
}
