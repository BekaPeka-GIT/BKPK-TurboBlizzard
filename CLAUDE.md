# Atari 8-bit / MADS — środowisko pracy

Programy w asemblerze 6502 dla Atari XL/XE, kompilowane Mad-Assemblerem (MADS), testowane w emulatorze Altirra. Komentarze w kodzie i komunikaty piszemy po polsku.

## Narzędzia

| Narzędzie | Ścieżka |
|---|---|
| MADS 2.1.7 | `./mads.exe` (źródło: `mads.pas`; dystrybucja 2.1.6 w `Mad-Assembler-2.1.6/`) |
| Altirra 4.31 | `C:\Users\barto\Altirra-4.31\Altirra64.exe` (wrapper: `run-xex.cmd`) |
| Dokumentacja MADS | `Mad-Assembler-2.1.6/doc/mads.html` (PL), `mads_eng.html` (EN) |
| Przykłady / biblioteki | `Mad-Assembler-2.1.6/examples/` (`atari.hea`, `LIBRARIES/`, `MACROS/`) |
| Analiza XEX | `python .claude/skills/xex-inspect/xex_inspect.py plik.xex [-d N]` |

## Komendy

```bash
./mads.exe prog.asm -o:prog.xex -l -t      # kompilacja + listing (.lst) + etykiety (.lab)
./mads.exe prog.asm -o:prog.xex -s         # cicho, tylko błędy
./mads.exe prog.asm -i:Mad-Assembler-2.1.6/examples -o:prog.xex   # z katalogiem include
./run-xex.cmd prog.xex                     # uruchom w Altirra (otwiera okno GUI)
```

MADS zwraca kod wyjścia ≠ 0 przy błędzie; komunikaty mają format `plik (linia) ERROR: ...`.

## Konwencje

- Programy XEX zaczynają się od `org $2000` (bezpiecznie powyżej DOS/MEMLO), chyba że loader wymaga inaczej (np. `org $0600` — strona 6 jest wolna).
- Punkt startu ustawiaj przez `run start` (MADS generuje segment RUNAD `$02E0`). `ini adres` → INITAD `$02E2` (kod musi kończyć się `rts`).
- Używaj nazw rejestrów zamiast gołych adresów (`SAVMSC = $58`, `COLOR2 = $2C6`, `RTCLOK = $12`…) — zdefiniuj je na górze pliku albo `icl 'atari.hea'`.
- Pamięć ekranu bierz z `SAVMSC` (`$58/$59`), nie zakładaj stałego adresu (`$0400` NIE jest pamięcią ekranu na Atari — to był błąd w `bekapeka_atari.asm`).
- Na ekran trafiają kody wewnętrzne ATASCII (internal), nie ATASCII: w MADS `dta d'TEKST'` zamiast `.byte "TEKST"`.
- Etykiety zaczynają się w kolumnie 1, mnemoniki są wcięte (MADS bez `-f` nie akceptuje mnemoników w kolumnie 1).
- Pliki `.xex`, `.lst`, `.lab` są artefaktami — nie edytuj ich ręcznie.

## Struktura

Pliki projektu leżą płasko w katalogu głównym (`bekapeka*.asm`, `loader*.asm`, `bkpkloaderv2.asm`). `RiverRaid.xex` to oryginał gry; `bkpk_riverraid.xex` = loader `bkpkloaderv2` (segment INITAD) + RiverRaid.

Kasety CAS z gier robi `python make_tape.py Gra.xex --title "NAZWA"` (skill `/atari-tape`): uniwersalny loader `tape_loader.asm` + `logo_data.inc`, wynik w `tape/<gra>/`. Starsze `riverraid_tape.asm`/`ninja_tape.asm` + `build*.cmd` to poprzednie wersje per gra.

Kasety Turbo Blizzard (bloki PWM CAS Altirry): `python make_blizzard.py Gra.xex --title "NAZWA"` → `tape/<gra>/<gra>_blizzard.cas` — sama gra w turbo, dla kogoś, kto ma Blizzarda na kartridżu / w ROM. Z `--loader` → `<gra>_blizzard_ldr.cas`: na początku loader Blizzarda 600 bodów z `TurboBlizzardCas/`, kaseta startuje na gołym Atari. Z ekranem BEKAPEKA (logo + pasek w trakcie turbo): `python make_tape.py Gra.xex --title "NAZWA" --turbo` → `tape/<gra>/<gra>_turbo.cas`. `--extract` robi odwrotnie CAS → XEX. Przykłady działających kaset w `TurboBlizzardCas/`.

## Agenci i skille (`.claude/`)

- Skille: `/mads-build`, `/atari-run`, `/atari-new`, `/xex-inspect`, `/atari-tape`
- Agenci: `asm-reviewer` (przegląd kodu 6502), `atari-hw-expert` (sprzęt/OS Atari, MADS), `xex-analyst` (rozbiór binariów XEX)
