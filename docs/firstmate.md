# Firstmate + Pi + Herdr

This profile is a deliberately scoped orchestration environment. The ordinary
`pi` command keeps its global Home Manager configuration. `firstmate-pi` is the
only entry point that loads Firstmate code.

## Managed inventory

All executable sources are immutable after the build. Versions change only by
editing `packages/agents/` and validating the resulting diff.

| Component | Version/revision | Owner and official source | Integrity lock | License |
|---|---|---|---|---|
| Pi | 0.84.1 | Nix; `earendil-works/pi` release | `sha256-aDyE…GEh0=` | MIT |
| Firstmate | `76355e20b4f44d968ca43c14e1bb21c100ac90d7` | Nix; `kunchenguid/firstmate` | `sha256-2WC0…P1A=` | MIT |
| Herdr | 0.8.0, protocol 19 artifact | Nix; `herdrdev/herdr` release | `sha256-1Tqf…gXg=` | Apache-2.0 |
| Treehouse | 2.1.1 | Nix; `kunchenguid/treehouse` release | `sha256-3qvr…R9M=` | MIT |
| no-mistakes | 1.46.0 | Nix; `kunchenguid/no-mistakes` release | `sha256-4dn4…LYg=` | MIT |
| gh-axi | 0.1.30 | Nix; `kunchenguid/gh-axi` | source `sha256-E9Sa…v5c=`, pnpm `sha256-2vlp…2d0=` | MIT |
| chrome-devtools-axi | 0.1.29 | Nix; `kunchenguid/chrome-devtools-axi` | source `sha256-ZiEt…h8I=`, pnpm `sha256-MhpA…YaU=` | MIT |
| lavish-axi | 0.1.50 | Nix; `kunchenguid/lavish-axi` | source `sha256-dg1T…Uw0=`, pnpm `sha256-y4Ke…4qY=` | MIT |
| tasks-axi | 0.2.5 | Nix; `kunchenguid/tasks-axi` | source `sha256-wi9r…6MQ=`, pnpm `sha256-BtnZ…cLg=` | MIT |
| quota-axi | 0.1.21 | Nix; `kunchenguid/quota-axi` | source `sha256-T9If…bUU=`, pnpm `sha256-5r9o…hwc=` | MIT |
| chrome-devtools-mcp | 1.7.0 | Nix; `ChromeDevTools/chrome-devtools-mcp`, including its pinned submodule | source `sha256-c23z…NIY=`, npm `sha256-yZdy…23c=` | Apache-2.0 |
| `gh`, Git, jq, Python, Node 24 | nixpkgs 26.05 closure | Nix/Home Manager | `flake.lock` | upstream licenses |

Full, non-abbreviated hashes live in `packages/agents/default.nix`. The table is
an audit index, not a second lock file.

## Ownership and private state

| State | Owner | Location | Nix rollback |
|---|---|---|---|
| Package declarations and launcher | this repository | `packages/agents/`, `modules/home/agents.nix` | restored |
| Firstmate code and Pi extensions | Nix | immutable store paths | restored |
| Firstmate data, config, projects and reports | Firstmate/user | `${XDG_DATA_HOME:-$HOME/.local/share}/firstmate` | preserved |
| Pi auth, sessions and trust | Pi/user | `~/.pi/agent` except two named HM files | preserved |
| Herdr config, socket, sessions and logs | Herdr/user | `~/.config/herdr` | preserved |
| GitHub auth and Keychain entries | `gh`/user | local config and Keychain | preserved |
| Chrome profiles and process state | Chrome/user | application-owned paths | preserved |

Home Manager owns only `~/.pi/agent/AGENTS.md` and
`~/.pi/agent/extensions/work-modes.ts`; it does not adopt the rest of `~/.pi`.
The profile does not copy Firstmate or its state into an application project.

## Launch

```sh
PI_OFFLINE=1 firstmate-pi --list-models
firstmate-pi
```

`firstmate-pi`:

1. resolves a writable `FM_HOME` outside `/nix/store`;
2. sets `FM_ROOT_OVERRIDE` to the pinned snapshot;
3. fixes `FM_BACKEND=herdr` and `FM_PI_HARNESS=pi`;
4. supplies Git, `gh`, jq, Python, Node 24 and agent CLIs only in its process
   closure, leaving the normal NVM shell unchanged;
5. points `CHROME_DEVTOOLS_AXI_MCP_PATH` at the built 1.7.0 JavaScript entry;
6. changes directory to the immutable Firstmate root;
7. disables Pi extension discovery and explicitly loads only:
   `fm-calm.ts`, `fm-primary-turnend-guard.ts`, and
   `fm-primary-pi-watch.ts`.

The launcher forwards Pi arguments but never adds `--approve`. It fails before
Pi starts if its root, extension allowlist, closure tools, backend, or private
home is unsafe. Starting it does not register a project or perform Git writes.

## Trust and execution surface

Firstmate and Pi run with the full permissions of the user; a Treehouse
worktree is isolation from accidental checkout changes, not a security sandbox.
The three TypeScript extensions execute in the Pi process. Firstmate shell
scripts can spawn Herdr workspaces and call all listed CLIs. `gh-axi` and
no-mistakes can affect remote repositories when explicitly instructed.
`chrome-devtools-axi` can control an attached browser through the pinned MCP.

No AXI `setup hooks` command is run. This profile does not install SessionStart
hooks in Claude, Codex, OpenCode, Pi, or the shell. It also does not run
`fm-bootstrap.sh install`, `/updatefirstmate`, `npm install -g`, `npx -y`, or
any `*-axi update` command.

## Initial operating limit

The first real-project pilot is one read-only scout with `yolo=false`. Do not
start parallel Firstmate tasks. The pinned revision predates a fully validated
durable-worktree-lease fix; parallel use remains blocked until a reviewed
revision containing that fix is pinned and isolation is retested.

Google Chrome is an external, user-owned application in this slice. Its
presence and signature are audited, but Nix does not install, update, or roll it
back. Relay, remote secondmates, tmux, alternative backends, Linux, and multiple
hosts are out of scope.
