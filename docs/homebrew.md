# Homebrew, terminal i narzędzia

Ten profil traktuje repo jako ścisłe źródło prawdy dla bezpośredniego
inwentarza Homebrew. `nix-homebrew` jest właścicielem instalacji w
`/opt/homebrew`, a nix-darwin generuje Brewfile i uruchamia Homebrew Bundle.
Użytkownikiem i właścicielem prefixu jest `<macos-user>`; Rosetta jest
wyłączona, a istniejący standardowy prefix może zostać zaadoptowany przez
`autoMigrate`.

## Dokładny inwentarz

Tap:

- `chipmk/tap`

Formulae:

- `go`
- `gh`
- `openjdk@21`
- `herdr`
- `chipmk/tap/docker-mac-net-connect`

Caski:

- `wezterm`
- `zulu@17`
- `font-jetbrains-mono-nerd-font`

Neovim nie należy do Homebrew. Jest instalowany przez Nix/Home Manager razem z
`ripgrep`, `fd` i wersjonowaną konfiguracją, więc polityka `zap` go nie usuwa.
Herdr oraz `docker-mac-net-connect` nie mają usługi ani autostartu.

## Aktualizacje i cleanup

Zwykły switch ma `autoUpdate = false`, `upgrade = false` i globalne automatyczne
aktualizacje Homebrew wyłączone. Aktualizacja wersji wymaga osobnej, jawnej
zmiany deklaracji albo inputów; switch nie wykonuje `brew update` ani
`brew upgrade`.

Polityka cleanup to `zap`. Usuwa ona elementy spoza Brewfile, a dla casków może
usunąć również powiązane dane aplikacji. Rollback generacji Nix nie przywraca
formulae, casków, tapów ani danych usuniętych przez `zap`.

## Codzienny rebuild

Zwykła aktywacja jest celowo tak krótka jak u Kuna:

```sh
./rebuild.sh
```

Wrapper od razu wywołuje `sudo darwin-rebuild switch` z
`--no-update-lock-file --no-write-lock-file`. Nie uruchamia wcześniej osobnego
checka ani nie zmienia `flake.lock`. `scripts/switch.sh` bez argumentów jest
zgodnym aliasem do tego samego przebiegu.

Opcjonalna kontrola przed aktywacją:

```sh
./scripts/check.sh
./scripts/switch.sh --dry-run
```

Dry-run używa `darwin-rebuild build --dry-run` i również nie aktualizuje ani nie
zapisuje locka. Aktualizacja wersji Nix jest osobną, jawną operacją:

```sh
nix flake update
./scripts/check.sh
./rebuild.sh
```

Usunięcie pakietu z deklaracji i późniejsze `./rebuild.sh` uruchomi Homebrew
`zap` bez drugiego pytania. To świadomie zaakceptowana semantyka repo jako
źródła prawdy.

## Migracja pyenv

Wrapper rozpoznaje wyłącznie dokładny czteroliniowy blok:

```sh
# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
```

Przed zapisem tworzy prywatny backup i manifest, po czym atomowo usuwa tylko ten
blok. Zmieniony albo powtórzony blok zatrzymuje operację. Recovery przywraca
backup tylko wtedy, gdy plik wynikowy nie został zmieniony i `pyenv` nadal
istnieje. Sam katalog `~/.pyenv` nie jest automatycznie kasowany.

## JDK i helper sieci

Profil zachowuje dwa niezależne JDK:

- Zulu JDK 17 z caska `zulu@17`, używany przez istniejące `JAVA_HOME` i narzędzia
  mobilne;
- OpenJDK 21 z formuły `openjdk@21` do nowszych buildów.

`docker-mac-net-connect` uruchamiaj tylko ręcznie, gdy potrzebujesz dostępu do
adresów kontenerów:

```sh
/opt/homebrew/opt/docker-mac-net-connect/bin/docker-mac-net-connect
```

Zatrzymaj go `Ctrl-C`. Nie używaj `brew services start`, bo utworzyłoby to
niezadeklarowany autostart.

## Granice recovery

Rollback generacji Nix nie odtwarza pakietów ani danych usuniętych przez
Homebrew `zap`. Przed większą zmianą inwentarza uruchom `scripts/audit.sh` i
zachowaj jego prywatny raport. Repo nie zapisuje środowiska, tokenów, Keychain,
auth ani treści sesji Herdr.
