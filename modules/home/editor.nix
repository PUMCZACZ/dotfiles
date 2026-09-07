{ pkgs, ... }:
{
  home.packages = [
    pkgs.fd
    pkgs.neovim
    pkgs.ripgrep
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  home.file = {
    ".config/nvim/init.lua".source = ../../home/nvim/init.lua;
    ".config/nvim/lazy-lock.json".source = ../../home/nvim/lazy-lock.json;
    ".config/nvim/lua/vim_config.lua".source = ../../home/nvim/lua/vim_config.lua;
    ".config/nvim/lua/keys.lua".source = ../../home/nvim/lua/keys.lua;
    ".config/nvim/lua/plugin.lua".source = ../../home/nvim/lua/plugin.lua;
    ".config/nvim/lua/plugins/colorscheme.lua".source = ../../home/nvim/lua/plugins/colorscheme.lua;
    ".config/nvim/lua/plugins/git.lua".source = ../../home/nvim/lua/plugins/git.lua;
    ".config/nvim/lua/plugins/lsp.lua".source = ../../home/nvim/lua/plugins/lsp.lua;
    ".config/nvim/lua/plugins/navigation.lua".source = ../../home/nvim/lua/plugins/navigation.lua;
    ".config/nvim/lua/plugins/ui.lua".source = ../../home/nvim/lua/plugins/ui.lua;
  };
}
