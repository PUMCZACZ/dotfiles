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
      sourceBinary ? binary,
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
        install -m 0755 ${if archive then sourceBinary else "$src"} "$out/bin/${binary}"
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

  codex = mkReleaseBinary {
    pname = "codex";
    version = "0.167.0";
    url = "https://github.com/openai/codex/releases/download/rust-v0.167.0/codex-aarch64-apple-darwin.tar.gz";
    hash = "sha256-SyKiqXG+J5HD4x+RLz53qI69ZKZYEqconMumXdZCX+k=";
    sourceBinary = "codex-aarch64-apple-darwin";
    description = "OpenAI coding agent for the terminal";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
  };

  pi = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "pi-coding-agent";
    version = "1.5.0";

    src = pkgs.fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v${finalAttrs.version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-qb8NgtWNKn0zf0rkFxtfyev/5CUJUnqDE2TEtlrfLN8=";
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

  observationalMemory = pkgs.stdenvNoCC.mkDerivation {
    pname = "pi-observational-memory";
    version = "78a1efcfdd46332253fb289724f05b26dfc7769e";

    src = pkgs.fetchFromGitHub {
      owner = "amosblomqvist";
      repo = "pi-observational-memory";
      rev = "78a1efcfdd46332253fb289724f05b26dfc7769e";
      hash = "sha256-iekslijEh0l1RQmrfYqtKIf2G2redwSlHtficqTNiW4=";
    };

    installPhase = ''
      runHook preInstall
      root="$out/share/pi-observational-memory"
      mkdir -p "$root"
      cp -R src agent package.json LICENSE "$root/"
      chmod -R u+w "$root"
      substituteInPlace "$root/src/index.ts" \
        --replace-fail '		const branch = ctx.sessionManager.getBranch() as Entry[];
		runtime.enabled = readGateFromLedger(branch);
		if (runtime.enabled) runtime.memoryRoot = ensureSessionMemory(ctx);' '		const branch = ctx.sessionManager.getBranch() as Entry[];
		runtime.enabled = readGateFromLedger(branch);
		if (branch.every((entry) => entry.type === "model_change" || entry.type === "thinking_level_change")) {
			runtime.enabled = true;
			pi.appendEntry(OM_ENABLED, { enabled: true });
		}
		if (runtime.enabled) runtime.memoryRoot = ensureSessionMemory(ctx);'
      substituteInPlace "$root/src/config.ts" \
        --replace-fail 'provider: "openrouter", id: "z-ai/glm-5.3"' 'provider: "openai-codex", id: "gpt-6.1-sol"' \
        --replace-fail 'thinking: "medium"' 'thinking: "low"'
      printf '%s\n' 'export { default } from "./src/index.ts";' > "$root/index.ts"
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      test -f "$out/share/pi-observational-memory/index.ts"
      test -f "$out/share/pi-observational-memory/src/spawn/launch.ts"
      grep -q 'branch.every((entry) => entry.type === "model_change"' "$out/share/pi-observational-memory/src/index.ts"
      grep -q 'return false;' "$out/share/pi-observational-memory/src/index.ts"
      test "$(grep -c 'provider: "openai-codex", id: "gpt-6.1-sol", thinking: "low"' "$out/share/pi-observational-memory/src/config.ts")" -eq 2
    '';

    strictDeps = true;
    meta = {
      description = "Pinned observational memory extension for Pi";
      homepage = "https://github.com/amosblomqvist/pi-observational-memory";
      license = lib.licenses.mit;
      platforms = [ "aarch64-darwin" ];
    };
  };

  interactiveSubagents = pkgs.stdenvNoCC.mkDerivation {
    pname = "pi-herdr-interactive-subagents";
    version = "3.7.2-herdr.1";

    src = pkgs.fetchFromGitHub {
      owner = "amosblomqvist";
      repo = "pi-interactive-subagents";
      rev = "c3e8b53c0754ae5ccc19fdab5a7481ec039bc2f7";
      hash = "sha256-CuHDL6JV1VZoYIe+P/hk9qGMK71GGF7QRHEohsPKA2s=";
    };

    installPhase = ''
      runHook preInstall
      root="$out/share/pi-herdr-interactive-subagents"
      mkdir -p "$root"
      cp -R pi-extension LICENSE config.json.example "$root/"
      chmod -R u+w "$root"
      index="$root/pi-extension/subagents/index.ts"
      done="$root/pi-extension/subagents/subagent-done.ts"
      status="$root/pi-extension/subagents/status.ts"
      substituteInPlace "$status" \
        --replace-fail 'join(dirname(fileURLToPath(import.meta.url)), "../..")' 'dirname(fileURLToPath(import.meta.url))'
      substituteInPlace "$index" "$done" \
        --replace-fail '@mariozechner/pi-coding-agent' '@earendil-works/pi-coding-agent' \
        --replace-fail '@mariozechner/pi-tui' '@earendil-works/pi-tui' \
        --replace-fail '@sinclair/typebox' 'typebox' \
        --replace-fail 'subagent_message' 'herdr_subagent_message'
      substituteInPlace "$index" \
        --replace-fail 'from "./tmux.ts"' 'from "./herdr.ts"' \
        --replace-fail 'subagents_list' 'herdr_subagents_list' \
        --replace-fail '"subagent",' '"herdr_subagent",' \
        --replace-fail 'pi.registerCommand("herdr_subagent"' 'pi.registerCommand("herdr-subagent"' \
        --replace-fail 'Use subagent with' 'Use herdr_subagent with' \
        --replace-fail '/subagent <agent>' '/herdr-subagent <agent>' \
        --replace-fail 'Subagents require tmux.' 'Subagents require Herdr.' \
        --replace-fail 'tmux not available' 'Herdr not available' \
        --replace-fail 'via tmux:' 'via Herdr:' \
        --replace-fail 'web-search", "index.ts"' 'web-search.ts"' \
        --replace-fail 'join(SUBAGENTS_DIR, "../../agents")' 'join(SUBAGENTS_DIR, "agents")'
      ${pkgs.python3}/bin/python3 ${./interactive-subagents/patch-index.py} "$index"
      cp ${./interactive-subagents/herdr.ts} "$root/pi-extension/subagents/herdr.ts"
      cp config.json.example "$root/pi-extension/subagents/config.json.example"
      rm "$root/pi-extension/subagents/tmux.ts"
      mkdir -p "$root/pi-extension/subagents/agents"
      cp ${./interactive-subagents/agents}/*.md "$root/pi-extension/subagents/agents/"
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      test -f "$out/share/pi-herdr-interactive-subagents/pi-extension/subagents/herdr.ts"
      grep -q 'name: "herdr_subagent"' "$out/share/pi-herdr-interactive-subagents/pi-extension/subagents/index.ts"
      ! grep -q 'from "./tmux.ts"' "$out/share/pi-herdr-interactive-subagents/pi-extension/subagents/index.ts"
    '';

    meta = {
      description = "Pinned interactive Pi subagents adapted for Herdr panes";
      homepage = "https://github.com/amosblomqvist/pi-interactive-subagents";
      license = lib.licenses.mit;
      platforms = [ "aarch64-darwin" ];
    };
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
      pkgs.agent-browser
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

      for tool in pi agent-browser herdr treehouse no-mistakes gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi git gh jq python3 node; do
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
    codex
    pi
    firstmate
    herdr
    interactiveSubagents
    observationalMemory
    treehouse
    ;
  agent-browser = pkgs.agent-browser;
  no-mistakes = noMistakes;
  gh-axi = ghAxi;
  chrome-devtools-axi = chromeDevtoolsAxi;
  lavish-axi = lavishAxi;
  tasks-axi = tasksAxi;
  quota-axi = quotaAxi;
  chrome-devtools-mcp = chromeDevtoolsMcp;
  firstmate-pi = firstmateLauncher;
}
