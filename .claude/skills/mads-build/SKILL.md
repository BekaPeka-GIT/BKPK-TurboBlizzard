---
name: mads-build
description: Kompiluje plik .asm Mad-Assemblerem (MADS) do .xex z listingiem i etykietami, interpretuje błędy i poprawia je. Użyj, gdy użytkownik prosi o kompilację, assemblację, zbudowanie programu Atari lub gdy zmieniono plik .asm.
argument-hint: "<plik.asm> [dodatkowe opcje mads]"
allowed-tools: Bash(./mads.exe:*), Read, Edit, Grep
---

# Kompilacja MADS

Cel: `$ARGUMENTS` (jeśli pusty — ostatnio edytowany `.asm` w katalogu głównym; zapytaj, gdy niejednoznaczne).

1. Uruchom z katalogu głównego projektu:
   ```bash
   ./mads.exe <plik>.asm -o:<plik>.xex -l:<plik>.lst -t:<plik>.lab <dodatkowe opcje>
   ```
   Gdy źródło używa `icl 'atari.hea'` lub makr z dystrybucji, dodaj `-i:Mad-Assembler-2.1.6/examples` (i ewentualnie `-i:Mad-Assembler-2.1.6/examples/MACROS`).
2. Kod wyjścia ≠ 0 → błąd. Format: `plik (linia) ERROR: komunikat`. Przeczytaj wskazaną linię źródła, popraw przyczynę (nie objaw) i skompiluj ponownie. Typowe przyczyny:
   - `Unexpected end of line` / `Undeclared label` — mnemonik w kolumnie 1 (brak wcięcia) albo literówka w etykiecie.
   - `Branch out of range` — skok warunkowy dalej niż ±127 B: odwróć warunek + `jmp`, albo użyj makro-skoków MADS (`jne`, `jeq`…).
   - `Value out of range` — wartość > $FF w trybie natychmiastowym: użyj `#<x` / `#>x`.
3. Po sukcesie podaj: zakres(y) adresów i rozmiar (z ostatnich linii wyjścia MADS lub `/xex-inspect`), adres startu (RUNAD) oraz ostrzeżenia.
4. Jeśli brak segmentu RUNAD (`run start`), ostrzeż — program nie wystartuje sam po załadowaniu.

Nie uruchamiaj emulatora automatycznie — od tego jest `/atari-run`.
