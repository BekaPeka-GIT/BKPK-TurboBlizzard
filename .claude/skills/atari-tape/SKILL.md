---
name: atari-tape
description: Robi plik kasetowy CAS (Atari, 600 bodów) z gry XEX — uniwersalny loader BEKAPEKA z ekranem (nazwa gry, logo, pasek postępu, adres strony) + gra. Sprawdza kolizje pamięci, sam wybiera miejsce na ekran, kompiluje i weryfikuje CAS. Użyj, gdy użytkownik chce przerobić grę XEX na kasetę / plik CAS / „turbo” z loaderem.
argument-hint: "<Gra.xex> [\"NAZWA GRY\"] [opcje]"
allowed-tools: Bash(python make_tape.py:*), Bash(python .claude/skills/xex-inspect/xex_inspect.py:*), Read, Grep
---

# Kaseta CAS z gry XEX

Cel: `$ARGUMENTS` — plik XEX i (opcjonalnie) nazwa gry na ekranie.

## 1. Zbuduj

Z katalogu głównego projektu:

```bash
python make_tape.py <Gra.xex> --title "NAZWA GRY"
```

Opcje:
- `--title` — nazwa gry, max 20 znaków, tylko wielkie litery/cyfry (tryb ANTIC 7). Domyślnie z nazwy pliku. Pod nią loader pisze „BY”, a dalej jest logo BekaPeka.
- `--color 36` — kolor nazwy (bajt koloru Atari hex, np. `36` czerwony, `9C` jasnoniebieski, `C8` zielony).
- `--word-colors 0,1` — kolor każdego słowa: `0` = `--color`, `1` = złoty, `3` = biały.
- `--name` — nazwa katalogu wyniku (domyślnie z nazwy pliku).
- `--screen 6000` — wymuś położenie ekranu (granica 4 KB), gdy automat wybierze źle.
- `--anim` — (eksperymentalne) animacja logo jak w `Animacja.mp4`: ikona budynku podskakuje, potem jasny pas przesuwa się przez logo. Działa w przerwaniach (VBI natychmiastowe + 2 DLI), także podczas odczytu taśmy; wyłączana przed INIT/RUN gry. Ekran zajmuje wtedy ok. 16,8 KB (`SCR4K-$1200 … SCR4K+$2FEF`), loader rośnie do ~$1002. Testowane tylko na KeystoneKapers.

- `--turbo` — loader BEKAPEKA (600 bodów) + gra w formacie Turbo Blizzard, czytana przez loader przy włączonym ekranie (logo, procenty, liczniki bloków 1 KB, pasek). Gra wczytuje się ok. 2× szybciej niż przy 600 bodach; kaseta zgodna z Blizzardem na kartridżu. Wyklucza `--anim`. Wynik `tape/<nazwa>/<nazwa>_turbo.cas` (+ `<nazwa>_turbo_ldr.bin/.lst/.lab`). Testowane w Altirze: River Raid, Ninja (INIT bez RUNAD).

Wynik: `tape/<nazwa>/<nazwa>.cas` (+ `tape_cfg.inc`, `tape_title.inc`, `<nazwa>_tape.bin/.lst/.lab`).

## 2. Oceń ostrzeżenia

- `BLAD:` — kaseta nie powstała. Typowe: gra > 255 bloków (~32 KB), segment na loaderze `$0600-…`, na stosie, na `$0300-$047F` (bufory kasety) albo w ROM `$C000+`. Tego loadera nie da się wtedy użyć — powiedz to wprost.
- Przed ostatnim INIT (gdy wczytano już cały plik) i przed RUNAD loader wyłącza ekran (DMA), zamyka C: i zeruje CDTMV1. Bez wyłączenia DMA ANTIC powtarzał śmieciową instrukcję DL z bitem DLI, a OS XL przestawał wołać odroczone VBI gry (Ninja: kolorowe pasy zamiast gry; na AltirraOS tego nie widać — testuj na OS XL).
- `brak RUNAD` — normalne, gdy grę startuje ostatni INIT (jak Ninja). Jeśli ostatni INIT wraca (`rts`), loader skoczy pod śmieciowy RUNAD — wtedy problem.
- `gra ma INIT` — zdeasembluj procedury INIT (agent `xex-analyst` albo krótki skrypt) i sprawdź, czy nie czyszczą/nadpisują pamięci ekranu podanej w raporcie ani strony zerowej `$CE-$EA`. Podmiana Display List i kolorów jest OK — loader je przywraca po każdym INIT.
- `strona 2` / `strona zerowa` — zwykle nieszkodliwe (np. `$0244` COLDST), ale wymień je.

## 3. Raport

Podaj: ścieżkę CAS, rozmiar, czas odczytu, położenie loadera i ekranu, INIT/RUN, ostrzeżenia z oceną. Zaproponuj test: `Altirra64.exe tape/<nazwa>/<nazwa>.cas` (start z wciśniętym START). Nie uruchamiaj emulatora bez prośby.

## Wariant: Turbo Blizzard

Gdy użytkownik chce Blizzarda (zamiast loadera BEKAPEKA):

Najpierw ustal, czy odbiorca ma Blizzarda na kartridżu / w ROM. Ma → bez `--loader`. Nie ma albo nie wiadomo → z `--loader` (albo zrób obie wersje, nazwy plików się nie gryzą).

```bash
python make_blizzard.py <Gra.xex> --title "NAZWA GRY"            # tape/<gra>/<gra>_blizzard.cas — dla kartridża/ROM
python make_blizzard.py <Gra.xex> --title "NAZWA GRY" --loader   # tape/<gra>/<gra>_blizzard_ldr.cas — na gołe Atari
python make_blizzard.py --extract plik.cas -o gra.xex             # CAS Blizzarda -> XEX
```

- `--loader` bez ścieżki dokleja `TurboBlizzardCas/Blizzard Turbo Loader 1.0.cas` (600 bodów, ~45 s) — kaseta startuje sama na gołym Atari. Sprawdzone w Altirze (River Raid, 2026-11-23).
- Blizzard ładuje surowy XEX w blokach po 1 KB (bez limitu ~32 KB jak BEKAPEKA, bez ekranu z logo). Nazwa: do 76 znaków, wielkie litery.
- Skrypt sam weryfikuje wynik (odczyt z powrotem + sumy). Format opisany w nagłówku `make_blizzard.py`; zgodny bajt w bajt z przykładami w `TurboBlizzardCas/`.
- Kolizji pamięci tu nie sprawdzamy. Loader Blizzarda ładuje się do `$0700-$132E`, ale przenosi kawałki kodu na strony 3–4 (`$03FD`, `$0458`…) i przełącza PORTB (`$D301`), czyli pracuje na kopii OS w RAM pod ROM-em — gra nadpisująca `$03xx-$04xx` albo RAM pod OS może się z nim gryźć.
- Podczas odczytu bloku turbo oryginalny loader wyłącza ekran (`NMIEN=0`, `DMACTL=0`, `IRQEN=0`, `sei`). Logo i pasek w trakcie turbo daje `make_tape.py --turbo` (własny odczyt w `tape_loader.asm`, `TURBO=1`).
- Format bitów (sprawdzone w Altirze): okres między opadającymi zboczami na SKSTAT bit 4; 0 = 181 µs, 1 = 272 µs, pilot = 499 µs (szerokość w CAS = cały okres). Blok 0 to tylko pilot + sync — jego bajt `00` nie ma zbocza kończącego, nie czytać go. Przy włączonym ekranie nie wolno mieć linii tekstu trybu ANTIC 2 (zła linia zatrzymuje CPU na ~80 cykli i psuje pomiar) — dlatego w TURBO status i adres strony są bitmapami trybu F.

## Pliki zestawu

| Plik | Rola |
|---|---|
| `make_tape.py` | całość: analiza, konfiguracja, MADS, CAS |
| `tape_loader.asm` | uniwersalny loader (nie kompiluj ręcznie, czyta `tape_cfg.inc`/`tape_title.inc` z `-i:`) |
| `logo_data.inc` | logo + teksty statusu, wspólne (`python gen_gfx.py bekapeka_logo.png logo_data.inc`, wymaga Pillow) |
| `build_cas.py`, `xex_info.py` | składanie/weryfikacja CAS, stałe paska postępu |
