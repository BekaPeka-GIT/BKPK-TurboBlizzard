---
name: atari-new
description: Tworzy nowy program Atari XL/XE w MADS z szablonu (org $2000, nazwy rejestrów OS, pamięć ekranu z SAVMSC, RUNAD), kompiluje go i sprawdza. Użyj, gdy użytkownik chce zacząć nowy program, demo lub test na Atari.
argument-hint: "<nazwa> [opis]"
allowed-tools: Read, Write, Bash(./mads.exe:*)
---

# Nowy program Atari

1. Nazwa pliku z pierwszego słowa `$ARGUMENTS` (małe litery, `_` zamiast spacji). Jeśli `<nazwa>.asm` już istnieje — NIE nadpisuj, zapytaj.
2. Przeczytaj [template.asm](template.asm), podstaw `{{NAZWA}}` (wielkimi literami w tekście ekranowym) i `{{OPIS}}`, zapisz jako `<nazwa>.asm` w katalogu głównym.
3. Jeśli użytkownik opisał, co program ma robić — zaimplementuj to w miejsce przykładowego `print`/`loop`, trzymając się konwencji z `CLAUDE.md`.
4. Skompiluj (`/mads-build`) i napraw ewentualne błędy.
5. Zaproponuj `/atari-run <nazwa>.xex`.
