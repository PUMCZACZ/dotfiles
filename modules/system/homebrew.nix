{
  config,
  lib,
  ...
}:
let
  profile = config.dotfiles.foundation;
  taps = [ "chipmk/tap" ];
  brews = [
    "go"
    "openjdk@21"
    "chipmk/tap/docker-mac-net-connect"
  ];
  casks = [
    "wezterm"
    "zulu@17"
    "font-jetbrains-mono-nerd-font"
  ];
  declarationData = {
    profile = profile.hostId;
    user = profile.user;
    prefix = profile.homebrewPrefix;
    inherit taps brews casks;
    cleanup = "zap";
    autoUpdate = false;
    upgrade = false;
    globalAutoUpdate = false;
  };
  lockHash = builtins.hashFile "sha256" ../../flake.lock;
  declarationHash = builtins.hashString "sha256" (builtins.toJSON declarationData);
  brewfileHash = builtins.hashString "sha256" config.homebrew.brewfile;
  desiredInventory = lib.concatLines (
    (map (name: "tap\t${name}") taps)
    ++ (map (name: "formula\t${name}") brews)
    ++ (map (name: "cask\t${name}") casks)
  );
in
{
  options.dotfiles.homebrew = {
    lockHash = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
    };
    declarationHash = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
    };
    brewfileHash = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
    };
    desiredInventory = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
    };
  };

  config = {
    assertions = [
      {
        assertion = profile.homebrewPrefix == "/opt/homebrew";
        message = "macos supports only the standard Apple Silicon Homebrew prefix";
      }
    ];

    dotfiles.homebrew = {
      inherit
        lockHash
        declarationHash
        brewfileHash
        desiredInventory
        ;
    };

    nix-homebrew = {
      enable = true;
      user = profile.user;
      enableRosetta = false;
      autoMigrate = true;
      mutableTaps = true;
    };

    homebrew = {
      enable = true;
      user = profile.user;
      prefix = profile.homebrewPrefix;
      inherit taps brews casks;
      global.autoUpdate = false;
      onActivation = {
        autoUpdate = false;
        upgrade = false;
        cleanup = "zap";
      };
    };

  };
}
