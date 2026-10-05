{
  lib,
  pkgs,
  ...
}:
let
  agentPackages = import ../../packages/agents { inherit pkgs; };
  desiredComponents = [
    [ "pi-coding-agent" "1.0.2" ]
    [ "firstmate-snapshot" "76355e20b4f44d968ca43c14e1bb21c100ac90d7" ]
    [ "herdr" "0.8.0" ]
    [ "pi-observational-memory" "78a1efcfdd46332253fb289724f05b26dfc7769e" ]
    [ "pi-herdr-interactive-subagents" "3.7.2-herdr.1" ]
    [ "treehouse" "2.1.1" ]
    [ "no-mistakes" "1.46.0" ]
    [ "gh-axi" "0.1.30" ]
    [ "chrome-devtools-axi" "0.1.29" ]
    [ "lavish-axi" "0.1.50" ]
    [ "tasks-axi" "0.2.5" ]
    [ "quota-axi" "0.1.21" ]
    [ "chrome-devtools-mcp" "1.7.0" ]
    [ "agent-browser" "0.27.0" ]
    [ "firstmate-pi" "76355e20b4f44d968ca43c14e1bb21c100ac90d7" ]
  ];
  desiredInventory = lib.concatLines (map (component: lib.concatStringsSep "\t" component) desiredComponents);
in
{
  options.dotfiles.firstmate.desiredInventory = lib.mkOption {
    type = lib.types.lines;
    readOnly = true;
    description = "Exact version inventory for the managed Firstmate profile.";
  };

  config = {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
        message = "The Firstmate profile supports only aarch64-darwin";
      }
    ];

    dotfiles.firstmate.desiredInventory = desiredInventory;

    home.packages = [
      pkgs.git
      pkgs.gh
      agentPackages.pi
      agentPackages.agent-browser
      agentPackages.herdr
      agentPackages.observationalMemory
      agentPackages.treehouse
      agentPackages.no-mistakes
      agentPackages.gh-axi
      agentPackages.chrome-devtools-axi
      agentPackages.lavish-axi
      agentPackages.tasks-axi
      agentPackages.quota-axi
      agentPackages.firstmate-pi
    ];

    home.file = {
      ".pi/agent/AGENTS.md".source = ../../home/pi/AGENTS.md;
      ".pi/agent/extensions/web-search.ts".source = ../../home/pi/extensions/web-search.ts;
      ".pi/agent/extensions/observational-memory".source =
        "${agentPackages.observationalMemory}/share/pi-observational-memory";
      ".pi/agent/extensions/herdr-interactive-subagents".source =
        "${agentPackages.interactiveSubagents}/share/pi-herdr-interactive-subagents/pi-extension/subagents";
    };
  };
}
