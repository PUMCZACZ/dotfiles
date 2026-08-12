{ osConfig, ... }:
let
  profile = osConfig.dotfiles.foundation;
in
{
  home = {
    username = profile.user;
    homeDirectory = profile.home;
    stateVersion = profile.homeStateVersion;

    file.${profile.canaryTarget}.text = profile.canaryContent;
  };
}
