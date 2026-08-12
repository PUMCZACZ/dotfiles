# macOS dotfiles

Declarative Apple Silicon macOS configuration using Determinate Nix,
nix-darwin, Home Manager, and nix-homebrew.

## Local identity

The public repository does not contain a macOS account name or absolute home
path. Repository scripts derive them for the current process:

```sh
export DOTFILES_USER="$(id -un)"
export DOTFILES_HOME="$HOME"
```

Flake commands that evaluate `darwinConfigurations.macos` must use `--impure`
because these two machine-local identity values are intentionally outside Git:

```sh
DOTFILES_USER="$(id -un)" DOTFILES_HOME="$HOME" \
  nix flake check --impure --no-build \
  --no-update-lock-file --no-write-lock-file
```

Prefer the repository commands, which export the values automatically:

```sh
./scripts/audit.sh
./scripts/check.sh
./scripts/switch.sh --dry-run
```

`./rebuild.sh` preserves only `DOTFILES_USER` and `DOTFILES_HOME` across its
explicit `sudo` boundary. A company laptop can use the same `macos` profile
without editing tracked files; its current account and `$HOME` become the local
identity for that evaluation.

## Safety

Authentication, Keychain data, sessions, caches, Firstmate runtime state, and
activation evidence stay outside Git and the Nix store. Updates, activation,
Homebrew cleanup, commits, and pushes are separate explicit operations. See
`docs/architecture.md`, `docs/migration.md`, and `docs/firstmate.md`.
