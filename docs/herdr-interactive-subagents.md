# Interaktywni subagenci Pi w Herdr

Zwykły `pi` w panelu Herdr ładuje port `amosblomqvist/pi-interactive-subagents` 3.7.2, commit `c3e8b53c0754ae5ccc19fdab5a7481ec039bc2f7`, z warstwą terminala `packages/agents/interactive-subagents/herdr.ts`. Pakiet i trzy domyślne role (`scout`, `researcher`, `worker`) buduje Nix (`packages/agents/default.nix`), a Home Manager symlinkuje go do `~/.pi/agent/extensions/herdr-interactive-subagents/`. Nie uruchamia niczego automatycznie ani nie zmienia profilu `firstmate-pi`.

## Użycie

Uruchom `pi` w panelu Herdr. W Pi: `/herdr-subagent scout Sprawdź moduł X` albo poproś model o `herdr_subagent({ agent: "scout", name: "x", task: "…" })`. `herdr_subagent_message({ name: "x", message: "…" })` steruje działającym agentem, odpowiada na `ask_question` i wznawia zakończoną sesję. `herdr_subagents_list` pokazuje dostępne role. Proces rodzica automatycznie odbiera zakończenie jako wiadomość `steer`; nie trzeba odpytywać logów. Przed pierwszym uruchomieniem po aktywacji Home Manager użyj `/reload` albo zrestartuj Pi.

Nazwa agenta jest uchwytem w rejestrze sesji rodzica. Herdr przechowuje układ terminali; własny plik JSONL Pi przechowuje rozmowę dziecka. Wznowienie odtwarza zapisane ograniczenia narzędzi i korzysta z tego samego JSONL, lecz w nowym panelu Herdr. Uruchomienie drugiego Pi na pliku, który nadal ma aktywny proces w Herdr, jest blokowane. Po restarcie rodzica, gdy dziecko wciąż pracuje, odbiór automatycznego wyniku nie jest odtwarzany; można wejść do tego panelu ręcznie, a następnie wznowić dopiero po zakończeniu procesu.

Domyślne role oraz observer i consolidator observational memory używają `openai-codex/gpt-6.1-sol` z reasoning `low`. Projektowe definicje `.pi/agents/<name>.md` i globalne `~/.pi/agent/agents/<name>.md` mogą nadpisywać role. `auto-exit: false` zostawia interaktywny panel otwarty, aż użytkownik zamknie Pi; `auto-exit: true` (domyślne role) kończy pracę po zadaniu. Agent `worker` może delegować tylko do `scout` i `researcher`. Port wspiera tylko procesy Pi, bez wykonywania Claude z pominięciem uprawnień.

Narzędzia są nazwane `herdr_*` i `/herdr-subagent`, a zwykły `subagent` nie jest instalowany. Nie instaluj `pi-config` jako całości ani oryginalnego pakietu tmux w globalnym profilu.

## Kontrola

- `node --test tests/herdr-interactive-subagents.test.ts` — testy adaptera bez modelu.
- `HERDR_LIVE_TEST=1 node --test tests/herdr-interactive-subagents.test.ts` — kontrolowany test rzeczywistego panelu, tylko wewnątrz Herdr; zamyka utworzony panel.
- `./tests/pi-agent-fixture.sh` oraz `likec4 validate docs/tasks/herdr-interactive-subagents` — profil i przepływ.

Kod upstream jest przypięty hashem, przepisanie API Pi i Herdr wykonuje budowa Nix, bez dynamicznego `pi install`. Autorskie sesje, rejestry, snapshoty sandboxów i skrypty startowe pozostają w prywatnych katalogach Pi, a nie w tym repo.
