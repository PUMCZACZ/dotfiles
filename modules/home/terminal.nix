{ pkgs, ... }:
{
  home.packages = [ pkgs.ngrok ];

  home.file.".config/wezterm/wezterm.lua".source = ../../home/wezterm/wezterm.lua;
}
