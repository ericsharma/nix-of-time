{ ... }:

{
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      add_newline = false;
      format = "$username$hostname$directory$git_branch$git_status$nix_shell$character";
      character = {
        success_symbol = "[›](bold blue)";
        error_symbol   = "[›](bold red)";
      };
      username = {
        show_always = true;
        format      = "[$user]($style)";
        style_user  = "bold green";
        style_root  = "bold red";
      };
      hostname = {
        ssh_only = false;
        format   = "[@$hostname]($style) ";
        style    = "bold green";
      };
      directory = {
        truncation_length = 3;
        truncate_to_repo  = true;
      };
      git_branch.symbol = " ";
      nix_shell = {
        symbol = " ";
        format = "[$symbol$state]($style) ";
      };
    };
  };
}
