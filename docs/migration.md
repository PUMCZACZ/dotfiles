# Migracja obecnego Maca

Ten slice przejmuje wyłącznie canary
`~/.config/dotfiles-managed/foundation`. Homebrew, Ghostty, Neovim, `.zshrc`,
NVM, pyenv, .NET, Docker, agenci, sekrety, auth i cache pozostają pod obecnymi
właścicielami.

## Bezpieczna kolejność

```sh
./scripts/audit.sh
./scripts/check.sh
./scripts/switch.sh --dry-run
```

`audit` zapisuje prywatny raport pod
`${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/audits/`. `check` wykonuje parse,
ShellCheck, fixture adopcji, Gitleaks, ewaluację flake i pełny build bez
aktywacji. `switch --dry-run` pokazuje dokładny store path, diff closure, stan
canary i jedyną komendę wymagającą `sudo`. Żadna z tych komend nie aktywuje
generacji.

Właściwe `./scripts/switch.sh` uruchamiaj dopiero po sprawdzeniu planu i osobnej
zgodzie. Nie ma opcji `--yes`. Skrypt ponownie sprawdza hash locka i deklaracji,
przenosi ewentualną kolizję jako jeden element do prywatnego backupu i dopiero
potem uruchamia `darwin-rebuild` z wcześniej zbudowanej closure.

## Backup i błąd

Manifest znajduje się pod
`${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/<run-id>/manifest.tsv`.
Zawiera cel, rodzaj, backup, status i czas. Symlinki nie są dereferowane.

- Błąd przed przeniesieniem canary nie zmienia aktywnego systemu ani celu.
- Błąd po przeniesieniu uruchamia recovery wyłącznie według wpisu `moved`.
- Recovery nie nadpisuje pliku albo symlinka utworzonego po błędzie.
- Backup i manifest nie są automatycznie usuwane.

Każdy błąd wskazuje etap, przyczynę, następną bezpieczną czynność i lokalny
artefakt, jeżeli powstał.

## Granice rollbacku

Generacja nix-darwin obejmuje konfigurację systemową i Home Manager. Rollback
nie cofa Homebrew, aplikacji, auth, sekretów, cache, Keychain ani danych
niezarządzanych. Nie usuwaj poprzednich generacji przed osobnym testem rollbacku.

Najpierw wyświetl generacje i wykonaj podgląd wskazanego numeru:

```sh
darwin-rebuild --list-generations
sudo nix-env -p /nix/var/nix/profiles/system --switch-generation N --dry-run
```

Po ręcznym sprawdzeniu numeru i osobnej zgodzie:

```sh
sudo darwin-rebuild --switch-generation N
./scripts/doctor.sh
```

Skrót do bezpośrednio poprzedniej generacji:

```sh
sudo darwin-rebuild --rollback
./scripts/doctor.sh
```

Rollback może zmienić aktywny profil i wymaga osobnej zgody. Samo listowanie
generacji i `--dry-run` nie przełącza systemu.
