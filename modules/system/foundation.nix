{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.foundation;
  nixUserPathFile = pkgs.writeText "dotfiles-nix-user-path" ''
    /etc/profiles/per-user/${cfg.user}/bin
  '';
in
{
  options.dotfiles.foundation = {
    hostId = lib.mkOption { type = lib.types.str; };
    user = lib.mkOption { type = lib.types.str; };
    home = lib.mkOption { type = lib.types.str; };
    platform = lib.mkOption { type = lib.types.str; };
    systemStateVersion = lib.mkOption { type = lib.types.int; };
    homeStateVersion = lib.mkOption { type = lib.types.str; };
    stateRoot = lib.mkOption { type = lib.types.str; };
    homebrewPrefix = lib.mkOption { type = lib.types.str; };
    canaryTarget = lib.mkOption { type = lib.types.str; };
    canaryContent = lib.mkOption { type = lib.types.lines; };
  };

  config = {
    # Determinate owns the Nix daemon and nix.conf. nix-darwin owns generations.
    nix.enable = false;
    nixpkgs.hostPlatform = lib.mkDefault cfg.platform;

    # Keep macOS' existing zsh startup files. nix-darwin enables its zsh module
    # by default, which would replace path_helper and hide /etc/paths.d entries.
    programs.zsh.enable = false;

    # The first generation was activated before the default above was made
    # explicit. Restore the exact files that nix-darwin preserved. Never
    # overwrite a file created by the user or another tool.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      for zshFile in zprofile zshrc zshenv; do
        currentFile="/etc/$zshFile"
        preservedFile="$currentFile.before-nix-darwin"
        if [[ ! -e "$currentFile" && ! -L "$currentFile" && -f "$preservedFile" ]]; then
          mv "$preservedFile" "$currentFile"
        fi
      done

      # macOS path_helper ignores symlinks in /etc/paths.d. Do not declare this
      # path through environment.etc: nix-darwin would own it as a symlink and
      # reject the regular file during the next activation.
      # shellcheck disable=SC1091
      . ${../../scripts/lib/profile-path.bash}
      profile_path_install_regular \
        ${lib.escapeShellArg (toString nixUserPathFile)} \
        /etc/paths.d/50-nix-user \
        /etc/static/paths.d/50-nix-user
    '';

    system = {
      primaryUser = cfg.user;
      stateVersion = cfg.systemStateVersion;
    };

    users.users.${cfg.user}.home = cfg.home;
  };
}
