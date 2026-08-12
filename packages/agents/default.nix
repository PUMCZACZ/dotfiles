{ pkgs }:
let
  inherit (pkgs) lib;

  mkReleaseBinary =
    {
      pname,
      version,
      url,
      hash,
      binary ? pname,
      archive ? true,
      description,
      homepage,
      license,
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version;

      src = pkgs.fetchurl { inherit url hash; };
      dontUnpack = !archive;
      sourceRoot = lib.optionalString archive ".";

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/bin"
        install -m 0755 ${if archive then binary else "$src"} "$out/bin/${binary}"
        runHook postInstall
      '';

      doInstallCheck = true;
      installCheckPhase = ''
        "$out/bin/${binary}" --version
      '';

      strictDeps = true;
      meta = {
        inherit description homepage license;
        mainProgram = binary;
        platforms = [ "aarch64-darwin" ];
      };
    };

  pi = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "pi-coding-agent";
    version = "0.84.1";

    src = pkgs.fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${finalAttrs.version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-aDyEJh9AuHC0p8zxgaSK1uzXGFOwES0bthdTlTDGEh0=";
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/pi" "$out/bin"
      cp -R . "$out/lib/pi"
      makeWrapper "$out/lib/pi/pi" "$out/bin/pi"
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      "$out/bin/pi" --version
    '';

    meta = {
      description = "Minimal terminal coding agent";
      homepage = "https://pi.dev/";
      license = lib.licenses.mit;
      mainProgram = "pi";
      platforms = [ "aarch64-darwin" ];
    };
  });

  firstmate = pkgs.stdenvNoCC.mkDerivation {
    pname = "firstmate-snapshot";
    version = "76355e20b4f44d968ca43c14e1bb21c100ac90d7";

    src = pkgs.fetchFromGitHub {
      owner = "kunchenguid";
      repo = "firstmate";
      rev = "76355e20b4f44d968ca43c14e1bb21c100ac90d7";
      hash = "sha256-2WC0+tnrYm+/sMqOkLBhu7SBqHIJy9Z254mvFa7jP1A=";
    };

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/firstmate"
      cp -R . "$out/share/firstmate"
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      test -x "$out/share/firstmate/bin/fm-bootstrap.sh"
      test -f "$out/share/firstmate/.pi/extensions/fm-calm.ts"
      test -f "$out/share/firstmate/.pi/extensions/fm-primary-turnend-guard.ts"
      test -f "$out/share/firstmate/.pi/extensions/fm-primary-pi-watch.ts"
    '';

    strictDeps = true;
    meta = {
      description = "Immutable Firstmate orchestration snapshot";
      homepage = "https://github.com/kunchenguid/firstmate";
      license = lib.licenses.mit;
      platforms = [ "aarch64-darwin" ];
    };
  };

  herdr = mkReleaseBinary {
    pname = "herdr";
    version = "0.8.0";
    url = "https://github.com/herdrdev/herdr/releases/download/v0.8.0/herdr-macos-aarch64";
    hash = "sha256-1Tqfk/zP38xVYyknv1EAL1rdCqeZC831CP+9hKxlgXg=";
    archive = false;
    description = "Terminal workspace and session backend for agents";
    homepage = "https://github.com/herdrdev/herdr";
    license = lib.licenses.asl20;
  };

  treehouse = mkReleaseBinary {
    pname = "treehouse";
    version = "2.1.1";
    url = "https://github.com/kunchenguid/treehouse/releases/download/v2.1.1/treehouse-v2.1.1-darwin-arm64.tar.gz";
    hash = "sha256-3qvrcVO60UZZ6Y2njeUzSv7K6qx+BZiLEGpIiGRnR9M=";
    description = "Git worktree manager with durable leases";
    homepage = "https://github.com/kunchenguid/treehouse";
    license = lib.licenses.mit;
  };

  noMistakes = mkReleaseBinary {
    pname = "no-mistakes";
    version = "1.46.0";
    url = "https://github.com/kunchenguid/no-mistakes/releases/download/v1.46.0/no-mistakes-v1.46.0-darwin-arm64.tar.gz";
    hash = "sha256-4dn4Sf1f/RTcwkYUJhTtPLBL2vpWXK5KI70rk/C6LYg=";
    description = "Evidence-backed delivery gate for Git changes";
    homepage = "https://github.com/kunchenguid/no-mistakes";
    license = lib.licenses.mit;
  };

  mkPnpmCli = import ./mk-pnpm-cli.nix { inherit pkgs; };

  ghAxi = mkPnpmCli {
    pname = "gh-axi";
    version = "0.1.30";
    src = pkgs.fetchFromGitHub {
      owner = "kunchenguid";
      repo = "gh-axi";
      rev = "75bc3e996bbd87efecaa3a4accbd35ca4bc970d9";
      hash = "sha256-E9SahmNcpY2a1Uy5CqLe3A5BIv1ecO/xZtZd6zGpv5c=";
    };
    pnpmDepsHash = "sha256-2vlp9u0I8gb5/VGEQwS9Z57/wOMzV+YW6U+/JL482d0=";
    main = "dist/bin/gh-axi.js";
    meta = {
      description = "Agent experience interface for GitHub CLI";
      homepage = "https://github.com/kunchenguid/gh-axi";
      license = lib.licenses.mit;
      mainProgram = "gh-axi";
    };
  };

  chromeDevtoolsAxi = mkPnpmCli {
    pname = "chrome-devtools-axi";
    version = "0.1.29";
    src = pkgs.fetchFromGitHub {
      owner = "kunchenguid";
      repo = "chrome-devtools-axi";
      rev = "1a91f5fa2a8e381e502b914116e9bafb1a819f48";
      hash = "sha256-ZiEtrZDvWV4xpIb68R0BE7H86pWuwm9QRV0o9JmAh8I=";
    };
    pnpmDepsHash = "sha256-MhpAmNmUAB8M0p8AlJpw80iRgWIdvKOjv88XAjFqYaU=";
    main = "dist/bin/chrome-devtools-axi.js";
    meta = {
      description = "Agent experience interface for Chrome DevTools";
      homepage = "https://github.com/kunchenguid/chrome-devtools-axi";
      license = lib.licenses.mit;
      mainProgram = "chrome-devtools-axi";
    };
  };

  lavishAxi = mkPnpmCli {
    pname = "lavish-axi";
    version = "0.1.50";
    src = pkgs.fetchFromGitHub {
      owner = "kunchenguid";
      repo = "lavish-axi";
      rev = "899747a3d7e03d1e3b8061fc3869331e514c2917";
      hash = "sha256-dg1TeQpTl/h/x6re2JvnGepgdoyq1o9mD5y1p60fUw0=";
    };
    pnpmDepsHash = "sha256-y4KeFqPF02TBSlP1mgyj5UFx0Q98ip890xYkBAYF4qY=";
    main = "dist/cli.mjs";
    meta = {
      description = "Agent interface for durable evidence and delivery";
      homepage = "https://github.com/kunchenguid/lavish-axi";
      license = lib.licenses.mit;
      mainProgram = "lavish-axi";
    };
  };

  tasksAxi = mkPnpmCli {
    pname = "tasks-axi";
    version = "0.2.5";
    src = pkgs.fetchFromGitHub {
      owner = "kunchenguid";
      repo = "tasks-axi";
      rev = "9a86c7c86a4617a5a4f00f28dcb9588b03897f8f";
      hash = "sha256-wi9rKhHpqNNLnINyilj+WJoL0Lz4zWebV67FEPP76MQ=";
    };
    pnpmDepsHash = "sha256-BtnZnvjHsPRchvlsy1vhkTf4+aYlx97Eh6RyjWpKcLg=";
    main = "dist/bin/tasks-axi.js";
    meta = {
      description = "Structured task backlog interface for agents";
      homepage = "https://github.com/kunchenguid/tasks-axi";
      license = lib.licenses.mit;
      mainProgram = "tasks-axi";
    };
  };

  quotaAxi = mkPnpmCli {
    pname = "quota-axi";
    version = "0.1.21";
    src = pkgs.fetchFromGitHub {
      owner = "kunchenguid";
      repo = "quota-axi";
      rev = "c539835faaaf284ee747cb7d79da89ed9b941f16";
      hash = "sha256-T9IflZDAPxIG+fV4+SB9xHRI1LNqmKZZytW2pZDVbUU=";
    };
    pnpmDepsHash = "sha256-5r9osgZibmqfjEHExoPLLVXSeebjrn7XWrv8J/FYhwc=";
    main = "dist/bin/quota-axi.js";
    meta = {
      description = "Provider quota interface for agents";
      homepage = "https://github.com/kunchenguid/quota-axi";
      license = lib.licenses.mit;
      mainProgram = "quota-axi";
    };
  };

  chromeDevtoolsMcp = pkgs.buildNpmPackage {
    pname = "chrome-devtools-mcp";
    version = "1.7.0";

    src = pkgs.fetchFromGitHub {
      owner = "ChromeDevTools";
      repo = "chrome-devtools-mcp";
      rev = "12f989a75bf6d24309d80cc59a71108e0c6c3df4";
      hash = "sha256-c23zIDDt01EqvnN0i0wPLwHEiy5lYCW0PR4cjOyONIY=";
      fetchSubmodules = true;
    };
    npmDepsHash = "sha256-yZdyUtfI4Je/XikpY34J5bmR8vx69pT8CUbI7H/+23c=";
    npmBuildScript = "build";
    PUPPETEER_SKIP_DOWNLOAD = "true";
    PUPPETEER_SKIP_CHROME_DOWNLOAD = "true";
    preBuild = ''
      node scripts/prepare.ts
    '';
    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/chrome-devtools-mcp" "$out/bin"
      cp -R package.json build node_modules "$out/lib/chrome-devtools-mcp/"
      makeWrapper ${pkgs.nodejs_24}/bin/node "$out/bin/chrome-devtools-mcp" \
        --add-flags "$out/lib/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js"
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      "$out/bin/chrome-devtools-mcp" --version
    '';

    meta = {
      description = "Chrome DevTools Model Context Protocol server";
      homepage = "https://github.com/ChromeDevTools/chrome-devtools-mcp";
      license = lib.licenses.asl20;
      mainProgram = "chrome-devtools-mcp";
      platforms = [ "aarch64-darwin" ];
    };
  };

  firstmateLauncher = (pkgs.writeShellApplication {
    name = "firstmate-pi";
    runtimeInputs = [
      pi
      herdr
      treehouse
      noMistakes
      ghAxi
      chromeDevtoolsAxi
      lavishAxi
      tasksAxi
      quotaAxi
      pkgs.git
      pkgs.gh
      pkgs.jq
      pkgs.python3
      pkgs.nodejs_24
      pkgs.curl
    ];
    text = ''
      fm_root=${lib.escapeShellArg "${firstmate}/share/firstmate"}
      fm_home=''${FM_HOME-}
      if [ -z "$fm_home" ]; then
        if [ -n "''${XDG_DATA_HOME-}" ]; then
          fm_home="$XDG_DATA_HOME/firstmate"
        elif [ -n "''${HOME-}" ]; then
          fm_home="$HOME/.local/share/firstmate"
        else
          printf 'firstmate-pi: HOME and XDG_DATA_HOME are unset\n' >&2
          exit 2
        fi
      fi

      case "$fm_home" in
        /*) ;;
        *) printf 'firstmate-pi: FM_HOME must be an absolute user path\n' >&2; exit 2 ;;
      esac
      case "$fm_home" in
        /|/nix|/nix/store|/nix/store/*)
          printf 'firstmate-pi: FM_HOME must remain outside the Nix store\n' >&2
          exit 3
          ;;
      esac

      if [ "''${FM_BACKEND-herdr}" != herdr ]; then
        printf 'firstmate-pi: this profile supports only FM_BACKEND=herdr\n' >&2
        exit 2
      fi

      for extension in \
        "$fm_root/.pi/extensions/fm-calm.ts" \
        "$fm_root/.pi/extensions/fm-primary-turnend-guard.ts" \
        "$fm_root/.pi/extensions/fm-primary-pi-watch.ts"; do
        if [ ! -f "$extension" ]; then
          printf 'firstmate-pi: missing pinned extension: %s\n' "$extension" >&2
          exit 3
        fi
      done

      mkdir -p "$fm_home" || exit 3
      resolved_home=$(python3 - "$fm_home" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
      )
      case "$resolved_home" in
        /|/nix|/nix/store|/nix/store/*)
          printf 'firstmate-pi: resolved FM_HOME is unsafe: %s\n' "$resolved_home" >&2
          exit 3
          ;;
      esac
      if [ ! -d "$resolved_home" ] || [ ! -w "$resolved_home" ]; then
        printf 'firstmate-pi: FM_HOME is not a writable directory: %s\n' "$resolved_home" >&2
        exit 3
      fi

      for tool in pi herdr treehouse no-mistakes gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi git gh jq python3 node; do
        if ! command -v "$tool" >/dev/null 2>&1; then
          printf 'firstmate-pi: required tool is unavailable: %s\n' "$tool" >&2
          exit 3
        fi
      done

      export FM_ROOT_OVERRIDE="$fm_root"
      export FM_HOME="$resolved_home"
      export FM_BACKEND=herdr
      export FM_PI_HARNESS=pi
      export CHROME_DEVTOOLS_AXI_MCP_PATH=${lib.escapeShellArg "${chromeDevtoolsMcp}/lib/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js"}

      cd "$fm_root"
      exec pi \
        --no-extensions \
        --extension "$fm_root/.pi/extensions/fm-calm.ts" \
        --extension "$fm_root/.pi/extensions/fm-primary-turnend-guard.ts" \
        --extension "$fm_root/.pi/extensions/fm-primary-pi-watch.ts" \
        "$@"
    '';
  }).overrideAttrs (_old: {
    pname = "firstmate-pi";
    version = "76355e20b4f44d968ca43c14e1bb21c100ac90d7";
    meta = {
      description = "Pinned Firstmate profile launcher for Pi and Herdr";
      homepage = "https://github.com/kunchenguid/firstmate";
      license = lib.licenses.mit;
      mainProgram = "firstmate-pi";
      platforms = [ "aarch64-darwin" ];
    };
  });
in
{
  inherit
    pi
    firstmate
    herdr
    treehouse
    ;
  no-mistakes = noMistakes;
  gh-axi = ghAxi;
  chrome-devtools-axi = chromeDevtoolsAxi;
  lavish-axi = lavishAxi;
  tasks-axi = tasksAxi;
  quota-axi = quotaAxi;
  chrome-devtools-mcp = chromeDevtoolsMcp;
  firstmate-pi = firstmateLauncher;
}
