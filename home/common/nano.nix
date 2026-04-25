{ ... }:

{
  programs.nano = {
    enable = true;
    syntaxHighlight = true;
    nanorc = ''
      set linenumbers
      set mouse
      set softwrap
      set atblanks
      set smarthome
      set tabsize 4
      set tabstospaces
      set autoindent
      set constantshow
      set indicator
      set zap
      set historylog
      set positionlog
    '';
  };
}
