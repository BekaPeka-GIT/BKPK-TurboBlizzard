---
name: atari-run
description: Uruchamia plik .xex w emulatorze Altirra (opcjonalnie najpierw go kompilując). Użyj, gdy użytkownik chce uruchomić, przetestować lub zobaczyć program Atari.
argument-hint: "<plik.xex|plik.asm>"
disable-model-invocation: true
allowed-tools: Bash(./mads.exe:*), Bash(./run-xex.cmd:*)
---

# Uruchomienie w Altirra

Cel: `$ARGUMENTS`.

1. Jeśli podano `.asm` (albo `.xex` jest starszy niż odpowiadający mu `.asm`) — najpierw skompiluj jak w `/mads-build`. Przy błędzie kompilacji przerwij.
2. Uruchom w tle (Altirra to okno GUI, nie kończy się samo):
   ```bash
   ./run-xex.cmd <plik>.xex
   ```
   Użyj `run_in_background`, żeby nie blokować sesji.
3. Powiedz użytkownikowi, czego powinien się spodziewać na ekranie, i poproś o informację zwrotną — Claude nie widzi okna emulatora.

Wskazówki debugowania w Altirra (do przekazania użytkownikowi w razie problemów):
- `F8` — debugger; `.loadsym <plik>.lab` ładuje etykiety z MADS; `bp <adres>` — breakpoint; `g` — kontynuuj.
- Altirra domyślnie emuluje 130XE z OS XL; zmiana: System → Configure System.
