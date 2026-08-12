{
  profileHome,
  profileUser,
  ...
}:
{
  imports = [
    ../../modules/system/foundation.nix
    ../../modules/system/homebrew.nix
  ];

  dotfiles.foundation = {
    hostId = "macos";
    user = profileUser;
    home = profileHome;
    platform = "aarch64-darwin";
    systemStateVersion = 7;
    homeStateVersion = "26.05";
    stateRoot = "${profileHome}/.local/state/dotfiles";
    homebrewPrefix = "/opt/homebrew";
    canaryTarget = ".config/dotfiles-managed/foundation";
    canaryContent = ''
      managed-by=home-manager
      profile=macos
      foundation-version=1
    '';
  };
}
