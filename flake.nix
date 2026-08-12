{
  description = "Reusable, declarative macOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      nix-homebrew,
      ...
    }:
    let
      system = "aarch64-darwin";
      profileUser = builtins.getEnv "DOTFILES_USER";
      profileHome = builtins.getEnv "DOTFILES_HOME";
      identityReady =
        if profileUser == "" || profileHome == "" then
          throw "Set DOTFILES_USER and DOTFILES_HOME and evaluate with --impure"
        else
          true;
      pkgs = import nixpkgs { inherit system; };
      agentPackages = import ./packages/agents { inherit pkgs; };
    in
    {
      packages.${system} = agentPackages;

      darwinConfigurations.macos = assert identityReady; nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          inherit inputs profileHome profileUser;
        };
        modules = [
          ./hosts/macos/default.nix
          home-manager.darwinModules.home-manager
          nix-homebrew.darwinModules.nix-homebrew
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${profileUser}.imports = [
              ./modules/home/foundation.nix
              ./modules/home/terminal.nix
              ./modules/home/editor.nix
              ./modules/home/agents.nix
            ];
          }
        ];
      };

      checks.${system}.darwin-system = self.darwinConfigurations.macos.system;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          gitleaks
          lua5_4
          shellcheck
          taplo
        ];
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
