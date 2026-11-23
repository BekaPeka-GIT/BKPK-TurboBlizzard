---
name: xex-inspect
description: Analizuje strukturę pliku Atari XEX — segmenty, adresy ładowania, RUNAD/INITAD, nakładanie się segmentów, padding, hexdump. Użyj przy debugowaniu loaderów, łączeniu plików XEX lub gdy program się nie uruchamia.
argument-hint: "<plik.xex> [-d N]"
allowed-tools: Bash(python .claude/skills/xex-inspect/xex_inspect.py:*)
---

# Inspekcja XEX

```bash
python .claude/skills/xex-inspect/xex_inspect.py $ARGUMENTS
```

`-d N` dodaje hexdump pierwszych N bajtów każdego segmentu (domyślnie 64).

Interpretacja:
- Segment `$02E0-$02E1` = RUNAD (start po załadowaniu całego pliku). Brak → plik nie wystartuje sam.
- Segment `$02E2-$02E3` = INITAD — kod wywoływany (`jsr`) zaraz po załadowaniu tego segmentu; musi kończyć się `rts`. Tak działają loadery/intra przed właściwym programem.
- Nakładające się segmenty: późniejszy nadpisuje wcześniejszy — zamierzone tylko w loaderach.
- Segmenty w `$0000-$007F` (strona zerowa OS), `$0200-$03FF` (wektory/bufory OS poza RUNAD/INITAD) lub `$D000-$D7FF` (rejestry sprzętowe) — zgłoś jako potencjalny problem.
- Program pod `$A000-$BFFF` koliduje z BASIC-iem, jeśli ten jest włączony (np. RiverRaid ładuje się do `$9FF0-$BFFF` → uruchamiać bez BASIC-a).

Aby zdeasemblować fragment, użyj agenta `xex-analyst`.
