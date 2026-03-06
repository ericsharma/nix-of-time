{ ... }:

{
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Eric Sharma";
        email = "sharma.e@husky.neu.edu";
      };

      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
      };

      pull.rebase = true;
      diff.algorithm = "histogram";
      init.defaultBranch = "main";
    };
  };
}
