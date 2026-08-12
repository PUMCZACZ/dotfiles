# Specyfikacja: odtwarzalna konfiguracja macOS

**Status:** zaakceptowany kierunek architektoniczny; realizacja etapami
**Data:** 2026-08-10
**Docelowy użytkownik:** `<macos-user>`
**Docelowa platforma pierwszego wydania:** Apple Silicon (`aarch64-darwin`)
**Docelowy system pierwszego wydania:** macOS 26
**Inspiracja:** `kunchenguid/dotfiles`, bez kopiowania prywatnych instrukcji, sekretów i ryzykownych ustawień

## 1. Cel

Powstaje prywatne repozytorium dotfiles, które pozwala:

1. przygotować świeżego Maca jednym kontrolowanym bootstrapem,
2. deklaratywnie instalować narzędzia CLI, aplikacje i ustawienia macOS,
3. przechowywać konfigurację terminala, shella, Neovim i agentów w Git,
4. aktualizować zależności jawnie i partiami,
5. wrócić do poprzedniej działającej generacji bez ręcznego odtwarzania systemu,
6. migrować obecnego Maca stopniowo, bez usuwania istniejących aplikacji i konfiguracji,
7. odtworzyć środowisko pracy bez umieszczania sekretów w repozytorium.

## 2. Potwierdzone decyzje

- Pierwsza wersja obsługuje jeden Mac Apple Silicon.
- Podstawą są Determinate Nix, Nix Flakes, nix-darwin i Home Manager.
- Aplikacje GUI lub pakiety słabo wspierane przez Nix mogą pozostać w Homebrew.
- Normalny rebuild nie aktualizuje automatycznie pakietów.
- `flake.lock` i pliki lock Neovim są wersjonowane.
- Homebrew podczas aktywacji nie używa `cleanup = "zap"`.
- Pierwsza aktywacja nie usuwa żadnego istniejącego pakietu ani caska.
- Pi pozostaje w zakresie i jest instalowany z oficjalnej dystrybucji.
- Pi startuje bez zewnętrznych rozszerzeń wykonujących kod.
- Herdr jest instalowany, ale nie uruchamia się automatycznie.
- Obecny Neovim z LSP i Treesitterem nie zostaje nadpisany przed równoległym smoke testem nowej konfiguracji.
- Ghostty pozostaje dostępny podczas testowania WezTerm.
- Codex i Pi zachowują logowanie, sesje, cache i tokeny poza Git oraz Home Managerem.
- Nie powstają aliasy omijające zgody agentów, takie jak `codex --full-auto` lub `claude --dangerously-skip-permissions`.

## 3. Stan początkowy potwierdzony 2026-08-10

### System

- Apple Silicon `arm64`.
- macOS `26.5.2`.
- użytkownik `<macos-user>`.
- lokalna nazwa hosta zgodna z profilem `macos`.
- Nix nie jest zainstalowany.
- Homebrew znajduje się w `/opt/homebrew`.

### Istotne istniejące narzędzia

- Codex i Claude znajdują się w `~/.local/bin`.
- Node.js 24 jest zarządzany przez NVM.
- Python jest zarządzany przez pyenv.
- .NET znajduje się w `/usr/local/share/dotnet`.
- Docker CLI znajduje się w `/usr/local/bin`.
- Neovim jest zainstalowany przez Homebrew.
- Obecna konfiguracja Neovim zawiera LSP, Treesitter, Telescope i nvim-tree.
- Obecny terminal GUI to Ghostty.
- Obecny prompt używa Oh My Posh.
- `.zshrc` zawiera konfiguracje NVM, pyenv, PHP, Composer, Android SDK, STM32CubeMX oraz profile Claude.

### Bezpośrednie pakiety Homebrew wymagające oceny migracyjnej

`docker-mac-net-connect`, `fd`, `gh`, `go`, `goreleaser`, `gradle`, `lazygit`, `neovim`, `ollama`, `open-ocd`, `openjdk@21`, `poppler`, `pyenv`, `tmux`, `uv`, `watchman`.

### Caski wymagające zachowania podczas pierwszej aktywacji

`codexbar`, `font-jetbrains-mono-nerd-font`, `ghostty`, `ngrok`, `zulu@17`.

## 4. Poza zakresem pierwszego wydania

- Intel Mac, Linux, NixOS i Windows.
- Automatyczne odtwarzanie danych aplikacji, historii przeglądarki i sesji agentów.
- Umieszczanie kluczy SSH, tokenów, haseł, plików auth i licencji w repozytorium.
- Automatyczne logowanie do Apple ID, GitHub, Codex, Claude, Pi i Docker.
- Automatyczne usuwanie istniejących aplikacji.
- Automatyczna migracja każdego językowego SDK do Nix podczas pierwszego wdrożenia.
- Własny cache binarny Nix, CI na zdalnym macOS i konfiguracja wielu hostów.
- Automatyczne instalowanie eksperymentalnych pakietów Pi.

## 5. Architektura

```text
repo dotfiles
├── flake.nix                    wejścia i definicja hosta
├── flake.lock                   przypięte rewizje
├── hosts/
│   └── macos/
│       └── default.nix          skład modułów dla obecnego Maca
├── modules/
│   ├── system/                  ustawienia macOS i nix-darwin
│   ├── homebrew/                aplikacje GUI i wyjątki
│   ├── shell/                   Zsh, Starship, aliasy, zmienne
│   ├── cli/                     bazowe narzędzia terminalowe
│   ├── terminal/                WezTerm i Herdr
│   ├── neovim/                  Neovim oraz pluginy
│   └── agents/                  Codex, Claude, Pi, wspólne instrukcje
├── home/
│   ├── nvim/
│   ├── wezterm/
│   ├── pi/
│   └── agents/
├── scripts/
│   ├── bootstrap.sh             pierwsze uruchomienie
│   ├── audit.sh                 raport istniejącego komputera
│   ├── check.sh                 walidacja bez aktywacji
│   ├── switch.sh                aktywacja bez aktualizacji
│   ├── update.sh                jawna aktualizacja wybranej warstwy
│   ├── history.sh               lista generacji
│   ├── rollback.sh              aktywacja starszej generacji
│   └── doctor.sh                końcowa diagnostyka
├── docs/
│   ├── fresh-machine.md
│   ├── migration.md
│   ├── updates.md
│   ├── rollback.md
│   └── manual-login-checklist.md
└── README.md
```

Konfiguracja ma moduły, ale pozostaje jednym repo i jednym hostem. Nie powstaje framework modułów ani generator konfiguracji.

## 6. Własność narzędzi

Jedno narzędzie ma jednego właściciela. Nie wolno instalować tej samej binarki równocześnie przez Nix, Homebrew i npm.

| Typ | Domyślny właściciel | Przykłady |
|---|---|---|
| Narzędzia CLI | Nix/Home Manager | `ripgrep`, `fd`, `fzf`, `jq`, `gh`, `lazygit`, `starship`, `neovim` |
| Ustawienia macOS | nix-darwin | Dock, Finder, klawiatura, trackpad |
| Aplikacje GUI | Homebrew casks | WezTerm, Ghostty podczas migracji, fonty |
| Pakiety macOS bez dobrego odpowiednika Nix | Homebrew formulae | wyjątki potwierdzone podczas implementacji |
| Codex CLI | oficjalny instalator OpenAI | binarka i aktualizacja; konfiguracja może być wersjonowana osobno |
| Pi | oficjalny pakiet npm Pi | binarka; konfiguracja autorska w repo |
| Sekrety i sesje | właściciel aplikacji / Keychain | auth Codex, auth Pi, SSH, tokeny |
| Wersje projektowe SDK | repo danego projektu | `global.json`, pliki Node, Docker Compose, dev shell |

## 7. Nix i kanał aktualizacji

Konfiguracja używa flakes, nie historycznego mechanizmu `nix-channel`.

Pierwsze wydanie przypina:

- `nixpkgs` do stabilnej gałęzi Darwin `26.05`,
- `nix-darwin` do gałęzi `nix-darwin-26.05`,
- Home Manager do `release-26.05`,
- `nix-darwin.inputs.nixpkgs.follows = "nixpkgs"`,
- `home-manager.inputs.nixpkgs.follows = "nixpkgs"`.

Dokładne rewizje zapisuje `flake.lock`. Normalne `switch` nie zmienia locka.

## 8. Homebrew

### Zasady

- Homebrew pozostaje warstwą dla aplikacji GUI i jawnych wyjątków.
- `homebrew.onActivation.cleanup` startuje jako `"none"`.
- `homebrew.onActivation.autoUpdate` jest wyłączone podczas zwykłego switcha.
- `homebrew.onActivation.upgrade` jest wyłączone podczas zwykłego switcha.
- Usuwanie pakietów wymaga osobnej, jawnej decyzji po porównaniu audytu z deklaracją.
- `zap` nie jest używane w pierwszym wydaniu.
- Pakiety Homebrew nie są przedstawiane jako objęte pełnym rollbackiem Nix.

### Migracja

Pierwsze wdrożenie zachowuje wszystkie obecne formulae i caski. Dopiero późniejszy etap klasyfikuje je na:

1. przeniesione do Nix,
2. deklarowane przez Homebrew,
3. zależności pośrednie pozostawione Homebrew,
4. świadomie usunięte przez użytkownika.

## 9. Shell

### Docelowo

- Zsh pozostaje domyślnym shellem.
- Home Manager włącza autosuggestions i syntax highlighting.
- Starship zastępuje Oh My Posh dopiero po wizualnym porównaniu.
- Aliasów jest mało i żaden nie omija zabezpieczeń narzędzi.
- `EDITOR` i `VISUAL` wskazują Neovim.
- Lokalne sekrety i prywatne zmienne mogą być ładowane z niewersjonowanego `~/.config/dotfiles/local.zsh`.

### Migracja istniejącego `.zshrc`

NVM, pyenv, PHP, Composer, Android SDK, STM32CubeMX i profile Claude są przenoszone osobnymi fragmentami. Pierwsza aktywacja nie usuwa obecnego `.zshrc`, dopóki odpowiedniki nie przejdą smoke testu.

## 10. Terminal i multiplexer

### WezTerm

- WezTerm jest instalowany i otrzymuje osobną konfigurację.
- Motyw bazuje na Rosé Pine Moon.
- Font bazuje na jednym wybranym Nerd Font.
- Ghostty pozostaje zainstalowany do czasu akceptacji WezTerm.
- Brak automatycznego ustawiania WezTerm jako jedynego terminala.

### Herdr

- Herdr jest instalowany jako terminalowy multiplexer agentów.
- Nie otrzymuje usługi uruchamianej przy logowaniu.
- Używa standardowego prefixu `Ctrl+B` tylko po sprawdzeniu konfliktu z tmux.
- Pierwszy smoke test obejmuje osobne panele z Codex i Pi.
- Dane sesji Herdr pozostają lokalne i nie trafiają do Git.

## 11. Neovim

### Cel

Powstaje czytelna konfiguracja do codziennej pracy w .NET, Vue, TypeScript, Nix i plikach infrastruktury. Nie zastępujemy działającego obecnego Neovim minimalną konfiguracją Kuna.

### Zachowywane możliwości

- LSP,
- Treesitter,
- wyszukiwanie plików i tekstu,
- diagnostyka,
- obsługa Git,
- lock pluginów,
- system clipboard,
- persistent undo.

### Inspiracje przyjmowane od Kuna

- `lazy.nvim`,
- Rosé Pine Moon,
- `which-key.nvim`,
- `gitsigns.nvim`,
- proste pliki pluginów pogrupowane funkcjonalnie,
- czytelne skróty z opisami.

### Redukcja duplikacji

- Snacks Picker zastępuje Telescope dopiero po porównaniu funkcji używanych obecnie.
- Oil zastępuje nvim-tree dopiero po zaakceptowaniu przepływu pracy.
- Lazygit pozostaje podstawowym pełnym UI Git; Neogit nie jest dodawany automatycznie.
- Gitsigns pozostaje lekką integracją w buforze.

### Bezpieczna migracja

Nowa konfiguracja uruchamia się początkowo pod osobnym `NVIM_APPNAME`. Obecne `~/.config/nvim` nie jest nadpisywane. Przełączenie następuje dopiero po smoke testach projektów HydroApp, CallPage i jednego projektu embedded.

### Rollback pluginów

Konfiguracja i `lazy-lock.json` są w Git. Rollback generacji przywraca konfigurację zarządzaną przez Home Manager, a skrypt rollback wykonuje kontrolowane `Lazy restore` dla wersji zapisanych w locku. Runtime pluginów nie jest przedstawiany jako czysto nixowy.

## 12. Agenci

### Codex

- Binarka pozostaje instalowana i aktualizowana oficjalnym instalatorem OpenAI.
- Konfiguracja nie wymusza trybu pełnej autonomii.
- Globalny `AGENTS.md` zawiera wyłącznie nasze świadome reguły.
- Auth, pamięci, sesje, cache, pluginy zewnętrzne i dane runtime nie trafiają do publicznego repo.
- Pierwsze uruchomienie wymaga ręcznego logowania.

Oficjalna komenda instalacji i aktualizacji:

```sh
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

### Claude

- Konfiguracja profili personal/work pozostaje zachowana.
- Nie powstaje alias z `--dangerously-skip-permissions`.
- Dane logowania pozostają lokalne.

### Pi

- Pi jest częścią pierwszego wydania i można go uruchomić komendą `pi`.
- Instalacja korzysta z oficjalnego pakietu i wyłącza lifecycle scripts npm.
- Uwierzytelnienie wykonuje użytkownik przez `/login`.
- `~/.pi/agent/auth.json`, sesje, cache, pobrane paczki i dane runtime nie trafiają do Git.
- Repo może zarządzać autorskim motywem, `settings.json`, `models.json` i później własnymi rozszerzeniami.
- Pierwsze wydanie nie instaluje `pi-openai-server-compaction`, `pi-web-access`, fast mode ani innych paczek wykonujących kod.
- Rozszerzenia są później dodawane pojedynczo po przeglądzie źródła i przypięciu wersji.

Oficjalna komenda instalacji:

```sh
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
```

Pierwsze uruchomienie:

```sh
cd /sciezka/do/projektu
pi
```

## 13. Sekrety i dane lokalne

Repozytorium nie zawiera:

- kluczy SSH i GPG,
- tokenów GitHub,
- tokenów API,
- plików auth Codex, Claude lub Pi,
- sesji i historii agentów,
- plików `.env`,
- prywatnych certyfikatów,
- danych Keychain,
- danych przeglądarek,
- prywatnego emaila Git, jeśli repo ma być publiczne.

`.gitconfig` może ładować niewersjonowany plik `~/.gitconfig.local` zawierający imię, email i konfigurację podpisywania. Bootstrap tworzy tylko przykład bez wartości.

Przed każdym pushem repo przechodzi skan sekretów. Wybór narzędzia nastąpi w planie implementacji; nie budujemy własnego skanera.

## 14. Bootstrap

### Kontrakt użytkownika

Na świeżym Macu użytkownik wykonuje:

```sh
git clone <PRYWATNY_LUB_PUBLICZNY_URL_REPO> ~/.dotfiles
cd ~/.dotfiles
./scripts/bootstrap.sh
```

`<PRYWATNY_LUB_PUBLICZNY_URL_REPO>` jest jedynym wymaganym parametrem zależnym od przyszłego repo GitHub.

### Zachowanie skryptu

`bootstrap.sh`:

1. kończy pracę, jeśli system nie jest macOS Apple Silicon,
2. potwierdza użytkownika `<macos-user>` i host `macos`,
3. uruchamia `audit.sh`,
4. zapisuje raport oraz kopię kolidujących plików w katalogu backupu z datą,
5. nie usuwa istniejących aplikacji,
6. instaluje Determinate Nix tylko, jeśli `nix` nie istnieje,
7. nie modyfikuje sekretów i sesji,
8. uruchamia walidację bez aktywacji,
9. wyświetla dokładny zakres pierwszego switcha,
10. prosi o potwierdzenie przed `sudo`,
11. uruchamia pierwszy `darwin-rebuild switch`,
12. uruchamia `doctor.sh`,
13. wyświetla checklistę ręcznego logowania.

Bootstrap jest idempotentny: ponowne uruchomienie nie duplikuje wpisów, nie resetuje stanu i nie reinstaluje bez potrzeby.

## 15. Komendy codzienne

### Audyt

```sh
./scripts/audit.sh
```

Pokazuje platformę, wersję systemu, właścicieli binarek, pakiety Homebrew, aktywną generację i kolizje plików.

### Walidacja

```sh
./scripts/check.sh
```

Wykonuje co najmniej:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.macos.system --dry-run
```

Nie modyfikuje aktywnego systemu.

### Aktywacja

```sh
./rebuild.sh
```

Od razu uruchamia `sudo darwin-rebuild switch` dla przypiętego locka. Nie
aktualizuje ani nie zapisuje `flake.lock`; check i dry-run są opcjonalnymi,
osobnymi komendami.

### Diagnostyka

```sh
./scripts/doctor.sh
```

Sprawdza obecność i podstawowe działanie Nix, Homebrew, Git, Zsh, Starship, Neovim, terminala, Herdr, Codex, Claude i Pi. Brak logowania do agenta jest raportowany jako krok ręczny, nie jako błąd instalacji.

## 16. Aktualizacje

Aktualizacje są jawne i rozdzielone, żeby awaria jednej warstwy nie zmieniała pozostałych.

### Nix

```sh
./scripts/update.sh nix
```

Semantyka:

```sh
nix flake update
./scripts/check.sh
./rebuild.sh
```

Skrypt pokazuje diff `flake.lock`. Nie wykonuje automatycznego commita ani pushu.

### Homebrew

```sh
./scripts/update.sh homebrew
```

Aktualizuje wyłącznie deklarowane pakiety po pokazaniu listy. Informuje przed wykonaniem, że rollback Nix nie cofnie aplikacji Homebrew.

### Neovim

```sh
./scripts/update.sh neovim
```

Aktualizuje pluginy, zapisuje zmianę `lazy-lock.json`, uruchamia headless smoke test i pokazuje diff. Nie wykonuje commita.

### Agenci

```sh
./scripts/update.sh agents
```

Aktualizuje Codex oraz Pi ich oficjalnymi ścieżkami po osobnym potwierdzeniu. Nie modyfikuje auth, sesji ani konfiguracji projektowej.

### Reguła publikacji aktualizacji

Po udanym update użytkownik ręcznie sprawdza diff, commituje locki i dopiero wtedy pushuje. Nie ma automatycznego aktualizowania z crona.

## 17. Generacje i rollback

### Historia

```sh
./scripts/history.sh
```

Pokazuje co najmniej numer generacji, datę, aktywną generację i odpowiadający commit repo, jeśli został zapisany w metadanych aktywacji.

### Powrót do poprzedniej generacji

```sh
./scripts/rollback.sh previous
```

### Powrót do wybranej generacji

```sh
./scripts/rollback.sh <NUMER_GENERACJI>
```

Skrypt:

1. pokazuje różnicę względem bieżącej generacji,
2. nie zmienia Git ani nie usuwa nowszych generacji,
3. prosi o potwierdzenie,
4. aktywuje istniejącą generację,
5. odtwarza pluginy Neovim według locka należącego do tej konfiguracji,
6. uruchamia `doctor.sh`.

Dokładna niskopoziomowa komenda nix-darwin zostaje ustalona i przetestowana podczas implementacji na wersji 26.05. Użytkownik korzysta wyłącznie ze stabilnego kontraktu `rollback.sh`.

### Ograniczenia rollbacku

Rollback Nix nie gwarantuje cofnięcia:

- aplikacji zaktualizowanych przez Homebrew,
- danych i migracji aplikacji GUI,
- macOS update,
- tokenów, sesji i cache,
- ręcznych zmian poza plikami zarządzanymi,
- zewnętrznych SDK instalowanych własnymi installerami.

Te granice muszą być jawne w `docs/rollback.md`.

## 18. Migracja obecnego Maca

Migracja jest sekwencyjna:

1. audyt i backup,
2. instalacja Nix bez przejęcia Homebrew,
3. ustawienia macOS o niskim ryzyku,
4. bazowe CLI,
5. Zsh i Starship z zachowaniem obecnych fragmentów środowiska,
6. WezTerm obok Ghostty,
7. nowy Neovim pod osobnym `NVIM_APPNAME`,
8. Pi i Herdr,
9. adopcja kolejnych pakietów Homebrew,
10. dopiero na końcu ewentualne usuwanie duplikatów po osobnej akceptacji.

Każdy etap ma własny switch, smoke test i możliwość cofnięcia. Nie wykonujemy big-bang migration.

## 19. Checklista ręczna po świeżej instalacji

Bootstrap kończy się listą:

- zaloguj się do Apple ID i Mac App Store,
- zaloguj GitHub CLI,
- odtwórz klucze SSH lub połącz 1Password SSH Agent,
- zaloguj Codex,
- zaloguj Claude,
- uruchom Pi i wykonaj `/login`,
- zaloguj Docker Desktop, jeśli wymagane,
- sprawdź profile Claude personal/work,
- sprawdź prywatne `.gitconfig.local`,
- odtwórz prywatne `.env` z menedżera sekretów,
- uruchom smoke test HydroApp, CallPage i embedded.

## 20. Weryfikacja

### Statyczna

- flake przechodzi ewaluację,
- build hosta przechodzi dry-run,
- skrypty przechodzą ShellCheck,
- repo przechodzi skan sekretów,
- nie ma duplikatów właścicieli binarek,
- wszystkie wersjonowane JSON-y i pliki Nix są poprawne składniowo.

### Runtime

- nowy terminal otwiera Zsh bez błędów,
- Starship renderuje prompt,
- Neovim uruchamia się bez błędów i potrafi otworzyć projekt,
- LSP działa w co najmniej pliku C#, Vue/TypeScript i Nix,
- wyszukiwanie plików i tekstu działa,
- Git status działa w terminalu i Neovim,
- Herdr tworzy workspace i rozpoznaje Codex oraz Pi,
- Codex uruchamia się bez utraty istniejącego auth,
- Pi uruchamia się po ręcznym loginie,
- `switch.sh` jest idempotentny,
- poprzednia generacja może zostać aktywowana przez `rollback.sh`.

### Fresh-machine rehearsal

Przed uznaniem rozwiązania za gotowe wykonujemy co najmniej jedno z:

1. instalacja na drugim czystym Macu,
2. instalacja na czystej maszynie wirtualnej macOS, jeśli dostępna i legalnie skonfigurowana,
3. kontrolowany test od zera po wykonaniu pełnego backupu obecnego Maca.

Bez takiego testu można deklarować lokalną migrację, ale nie pełne odtworzenie świeżego komputera.

## 21. Kryteria akceptacji

1. Użytkownik przygotowuje świeżego Apple Silicon Maca przez clone i jedną komendę bootstrap.
2. Bootstrap nie usuwa istniejących aplikacji ani danych bez oddzielnej zgody.
3. Ponowne uruchomienie bootstrapu i switcha nie powoduje duplikacji ani nieoczekiwanych zmian.
4. Normalny switch nie aktualizuje `flake.lock`, Homebrew, Neovim ani agentów.
5. Aktualizacja każdej warstwy jest jawna, pokazuje diff i nie wykonuje automatycznego commita/pushu.
6. Poprzednią generację Nix można aktywować jedną komendą.
7. Ograniczenia rollbacku Homebrew i danych aplikacji są widoczne przed aktualizacją.
8. Sekrety, auth, sesje i cache nie znajdują się w Git.
9. Obecny Mac może być migrowany etapami bez utraty działającego Ghostty, Neovim, NVM, pyenv, .NET i Docker.
10. Pi, Codex, Claude i Herdr są dostępne, ale żaden agent nie startuje z automatycznie pominiętymi zabezpieczeniami.
11. Nowa konfiguracja Neovim zachowuje LSP i Treesitter obecnej konfiguracji.
12. Dokumentacja jasno opisuje instalację, aktualizacje, rollback, odzyskanie sekretów i kroki ręczne.

## 22. Podział na przyszłe plany wykonawcze

Ta specyfikacja opisuje docelowy system. Implementacja powinna powstać w kontrolowanych vertical slice'ach:

1. fundament repo + bootstrap + check + switch,
2. bezpieczna migracja Homebrew i bazowych CLI,
3. shell + Starship + zmienne lokalne,
4. WezTerm + Herdr,
5. Neovim,
6. Codex + Claude + Pi,
7. update + history + rollback + doctor,
8. rehearsal świeżego komputera i dokumentacja końcowa.

Każdy slice wymaga osobnego planu, weryfikacji i akceptacji przed przejściem do następnego.

## 23. Źródła bazowe

- Inspiracja: <https://github.com/kunchenguid/dotfiles>
- Nix update: <https://nix.dev/manual/nix/2.18/command-ref/new-cli/nix3-flake-update>
- nix-darwin: <https://github.com/nix-darwin/nix-darwin>
- Home Manager: <https://github.com/nix-community/home-manager>
- Determinate Nix: <https://docs.determinate.systems/determinate-nix/>
- Codex CLI: <https://learn.chatgpt.com/docs/codex/cli>
- Codex AGENTS.md: <https://learn.chatgpt.com/docs/agent-configuration/agents-md>
- Pi: <https://pi.dev/docs/latest>
- Herdr: <https://github.com/ogulcancelik/herdr>
