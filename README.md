# BKPK TurboBlizzard — kasety Atari z gier XEX

Zestaw narzędzi do robienia plików kasetowych **CAS** dla Atari XL/XE z gier w formacie **XEX**:

- **`make_tape.py`** — kaseta z loaderem **BEKAPEKA**: nazwa gry, logo, procenty, liczniki bloków i pasek postępu. Gra jest nagrana zwykłym zapisem 600 bodów albo, z opcją `--turbo`, w formacie **Turbo Blizzard**. W obu przypadkach ekran z logo i paskiem jest widoczny przez całe wczytywanie.
- **`make_blizzard.py`** — „czysta” kaseta Turbo Blizzard, bez ekranu BEKAPEKA, w takim samym formacie jak oryginalne kasety Blizzarda. Opcjonalnie z loaderem Blizzarda na początku. Umie też wyciągnąć XEX z kasety Blizzarda.

Gotowe kasety otwiera się w emulatorze **Altirra** albo nagrywa na prawdziwą taśmę.

---

## 1. Czego potrzebujesz

| Program | Po co | Uwagi |
|---|---|---|
| Windows | `mads.exe` to program dla Windows | skrypty Pythona działają wszędzie, ale kompilacja loadera wymaga `mads.exe` |
| Python 3.8+ | wszystkie skrypty `.py` | bez dodatkowych bibliotek (Pillow tylko dla `gen_gfx.py`) |
| MADS (Mad-Assembler) | kompiluje loader | **jest w repo**: `mads.exe` (2.1.7) i `Mad-Assembler-2.1.6/` |
| [Altirra](https://www.virtualdub.org/altirra.html) | test kaset w emulatorze | zalecana 4.x |
| plik gry `.xex` | to, co chcesz nagrać | **gier nie ma w repo** — użyj własnych |

Sprawdź instalację:

```bat
python --version
mads.exe
```

---

## 2. Szybki start

Wszystkie polecenia uruchamiaj **z katalogu głównego repo** (tam, gdzie leży `make_tape.py`).

```bat
python make_tape.py MojaGra.xex --title "MOJA GRA" --turbo
```

Wynik: `tape\mojagra\mojagra_turbo.cas`. Otwórz go w Altirze (*File → Boot Image…* albo przeciągnij plik na okno). Komputer sam wystartuje z kasety, pojawi się ekran z logo, a po wczytaniu uruchomi się gra.

---

## 3. Który wariant wybrać

| Chcesz… | Polecenie | Plik wynikowy | Czas (gra ~16 KB) |
|---|---|---|---|
| logo + pasek, działa na każdym Atari, najbezpieczniej | `make_tape.py Gra.xex` | `tape/gra/gra.cas` | ~5 min |
| logo + pasek, szybciej (turbo) | `make_tape.py Gra.xex --turbo` | `tape/gra/gra_turbo.cas` | loader ~70 s + gra ~40 s |
| kaseta dla kogoś z **Blizzardem na kartridżu / w ROM** | `make_blizzard.py Gra.xex` | `tape/gra/gra_blizzard.cas` | ~40 s |
| oryginalny loader Blizzarda + gra, bez logo | `make_blizzard.py Gra.xex --loader` | `tape/gra/gra_blizzard_ldr.cas` | loader ~45 s + gra ~40 s |

Kaseta `--turbo` z `make_tape.py` pozostaje zgodna z Blizzardem na kartridżu, bo część z grą ma dokładnie format Blizzarda.

---

## 4. `make_tape.py` — kaseta z ekranem BEKAPEKA

```bat
python make_tape.py <Gra.xex> [opcje]
```

### Opcje

| Opcja | Znaczenie | Przykład |
|---|---|---|
| `--title "TEKST"` | nazwa gry na ekranie: max **20 znaków**, wielkie litery, cyfry, spacja i znaki interpunkcyjne. Domyślnie nazwa pliku | `--title "RIVER RAID"` |
| `--color XX` | kolor nazwy (bajt koloru Atari, hex). Domyślnie `36` (czerwony) | `--color 9C` (jasnoniebieski), `C8` (zielony) |
| `--word-colors a,b,…` | kolor każdego słowa nazwy: `0` = `--color`, `1` = złoty, `3` = biały; ostatni dotyczy reszty słów | `--word-colors 0,1` |
| `--turbo` | gra w formacie Turbo Blizzard (szybciej, ekran nadal widoczny) | |
| `--anim` | animacja logo (podskok ikony + odblask). **Nie działa z `--turbo`**, ekran zajmuje ok. 16,8 KB | |
| `--name nazwa` | nazwa katalogu i plików wyniku (domyślnie z nazwy pliku XEX) | `--name rr` |
| `--screen 6000` | wymuś położenie ekranu loadera (granica 4 KB, hex), gdy automat wybierze źle | |
| `--desc "Opis"` | opis zapisany w nagłówku pliku CAS | |

### Przykłady

```bat
python make_tape.py RiverRaid.xex --title "RIVER RAID" --word-colors 0,1 --color 9C --turbo
python make_tape.py Ninja.xex --title "NINJA" --turbo
python make_tape.py KeystoneKapers.xex --title "KEYSTONE KAPERS" --anim
```

### Co wypisuje skrypt

```
Gra:    RiverRaid.xex -> "RIVER RAID", 2 segmentow, 8220 B danych, 9 blokow
INIT:   brak
RUN:    $9FF6
Loader: $0600-$0FB0, ekran $1E00-$3CCF
CAS:    tape\riverraid\riverraid_turbo.cas (12797 B, ... weryfikacja OK)
Czas:   loader ok. 71 s (600 bodow), gra ok. 25 s (turbo)
```

- **`BLAD:`** — kaseta **nie powstała**. Najczęstsze przyczyny: gra nadpisuje pamięć loadera (`$0600-…`), stos, bufory systemu (`$0300-$047F`) albo ROM, za mało wolnej pamięci na ekran, gra za duża.
- **`UWAGA:`** — kaseta powstała, ale warto ją przetestować:
  - `brak RUNAD` — gra startuje z ostatniego INIT. To normalne, jeśli ten INIT nie wraca (np. Ninja).
  - `gra ma INIT` — procedury INIT gry mogą wyczyścić pamięć ekranu loadera. Loader po każdym INIT przywraca swój ekran, ale nie odtworzy zamazanej grafiki.
  - `strona 2` — gra zmienia zmienne systemu, zwykle nieszkodliwe.

### Pliki wyniku (`tape/<nazwa>/`)

| Plik | Co to |
|---|---|
| `<nazwa>.cas` / `<nazwa>_turbo.cas` | **kaseta — to jest plik, którego używasz** |
| `<nazwa>_tape.bin/.lst/.lab`, `<nazwa>_turbo_ldr.*` | skompilowany loader, listing i etykiety (do diagnostyki) |
| `tape_cfg.inc`, `tape_title.inc` | konfiguracja loadera wygenerowana dla tej gry (nie edytuj ręcznie) |

---

## 5. `make_blizzard.py` — czysty Turbo Blizzard

```bat
python make_blizzard.py <Gra.xex> [--title "NAZWA"] [--loader [plik.cas]] [-o wynik.cas]
python make_blizzard.py --extract <kaseta.cas> [-o gra.xex]
```

| Opcja | Znaczenie |
|---|---|
| `--title` | nazwa w nagłówku Blizzarda, do 76 znaków (zamieniana na wielkie litery). Domyślnie nazwa pliku |
| `--loader` | dokleja na początek taśmy loader Blizzarda (600 bodów), żeby kaseta startowała na Atari bez kartridża. Bez ścieżki szuka pliku `TurboBlizzardCas/Blizzard Turbo Loader 1.0.cas`, **którego nie ma w repo** — podaj ścieżkę do własnej kopii: `--loader "C:\sciezka\Blizzard Turbo Loader 1.0.cas"` |
| `--extract` | działa odwrotnie: wyciąga XEX z kasety Blizzarda i sprawdza sumy kontrolne |
| `-o` | ścieżka pliku wynikowego (domyślnie `tape/<gra>/<gra>_blizzard[_ldr].cas`) |

Po zbudowaniu skrypt sam odczytuje kasetę z powrotem i porównuje ją z XEX (`Weryfikacja OK`).

---

## 6. Wczytywanie

### W Altirze

1. *File → Boot Image…* i wybierz plik `.cas` (albo przeciągnij go na okno, albo uruchom `Altirra64.exe plik.cas`).
2. Altirra sama włącza komputer z wciśniętym START i odtwarza taśmę.
3. Kolejne etapy:
   - około 20 s ciszy (rozbieg taśmy), potem wczytywanie loadera (pasek SIO u dołu),
   - ekran z logo i komunikat `OTWIERANIE KASETY - POCZEKAJ CHWILE...`,
   - `LADOWANIE  42%  004/009 ZOSTALO 005`, pasek rośnie po każdym bloku,
   - ekran gaśnie i startuje gra.

Kasety turbo nie wymagają w Altirze żadnych dodatkowych ustawień: Blizzard używa zwykłej linii danych magnetofonu.

### Na prawdziwym Atari (magnetofon XC12 / 1010 / XCA12 itp.)

1. Nagraj plik CAS na taśmę albo odtwarzaj go z komputera/telefonu przez interfejs kasetowy. Plik CAS trzeba najpierw zamienić na dźwięk (WAV) programem, który obsługuje bloki turbo PWM, np. edytorem taśm w Altirze (Tape Editor), jeśli twoja wersja zapisuje WAV. Kasety 600 bodów obsługuje każdy konwerter CAS→WAV.
2. Przewiń taśmę na początek nagrania.
3. Wyłącz komputer. Trzymając **START** (na XL/XE najlepiej **START + OPTION**), włącz komputer. Usłyszysz sygnał.
4. Wciśnij **PLAY** na magnetofonie, potem dowolny klawisz na Atari.
5. Dalej jak w Altirze.

**Kaseta Blizzard bez loadera** (`make_blizzard.py` bez `--loader`): wczytuj ją tak, jak każą instrukcje twojego Blizzarda (kartridż / ROM).

> Wersję `--turbo` testowano w Altirze (River Raid, Ninja). Na prawdziwym sprzęcie nie była jeszcze sprawdzana. Jeśli tam zawiedzie, użyj wersji 600 bodów (bez `--turbo`).

---

## 7. Błędy podczas wczytywania

Jeśli coś pójdzie źle, loader pokazuje w linii statusu:

```
BLAD KASETY $8F  ETAP D
```

**Kod błędu:**

| Kod | Znaczenie | Co zrobić |
|---|---|---|
| `$8F` | zła suma kontrolna bloku (zakłócenia, zła głośność, uszkodzona taśma) | przewiń i wczytaj jeszcze raz; zmień głośność/azymut głowicy; w turbo spróbuj wersji 600 bodów |
| `$80` | wciśnięto BREAK | — |
| `$88` | koniec pliku w złym miejscu (taśma ucięta lub niezgodna z loaderem) | zrób kasetę od nowa |
| `$8A`, `$8B`, `$8C` | (600 bodów) błędy SIO: brak sygnału / timeout | sprawdź połączenie i głośność |

**Etap** (gdzie wystąpił błąd):

| Litera | Wersja 600 bodów | Wersja `--turbo` |
|---|---|---|
| `O` | otwieranie magnetofonu | — |
| `T` | — | blok 0 Blizzarda (długi pilot) |
| `N` | — | nagłówek Blizzarda (nazwa) |
| `H` | nagłówek segmentu XEX | nagłówek segmentu XEX / kolejny blok |
| `E` | koniec segmentu | — |
| `D` | dane segmentu | dane segmentu / kolejny blok |

**Ekran wisi na `OTWIERANIE KASETY…`:** loader nie słyszy sygnału. Sprawdź, czy taśma się kręci i czy głośność jest odpowiednia. W wersji turbo loader czeka na pilot Blizzarda, więc upewnij się, że to kaseta z `--turbo`.

---

## 8. Ograniczenia

- **Pamięć:** gra nie może ładować się na loader (`$0600` do ok. `$1000`), stos, bufory systemu `$0300-$047F`, zmienne loadera na stronie zerowej (`$CE-$EA`, w turbo `$CE-$F0`) ani ROM `$C000+`. Ekran loadera (ok. 6,2 KB, w turbo ok. 7,9 KB, z `--anim` ok. 16,8 KB) skrypt sam umieszcza w wolnej pamięci.
- **Rozmiar:** wersja 600 bodów do ok. 32 KB (255 bloków po 128 B), turbo do ok. 63 KB.
- **Procedury INIT gry** mogą zamazać ekran loadera. Loader przywraca listę wyświetlania i kolory, ale nie grafikę.
- `--anim` i `--turbo` się wykluczają.
- `--title` w `make_tape.py`: tylko znaki trybu ANTIC 7 (wielkie litery, cyfry, spacja, interpunkcja), max 20.

---

## 9. Jak to działa (w skrócie)

**Taśma `--turbo`:**

```
[rekordy boot 600 bodów = loader BEKAPEKA]  [EOF]
[3 s ciszy] [blok 0: długi pilot]  [nagłówek: nazwa 76 zn.]  [bloki danych: 1024 B XEX]...
```

- **Format Turbo Blizzard** (bloki PWM pliku CAS, 44,1 kHz): bit = okres między opadającymi zboczami na linii danych SIO. `0` = 181 µs, `1` = 272 µs, pilot = 499 µs, najstarszy bit pierwszy. Blok: pilot, 2 impulsy synchronizacji, dane, suma (mod 256), bajt kończący.
- **Odczyt w loaderze:** każde zbocze restartuje timer POKEY (kanały 3+4, 16 bitów, 1,79 MHz), a flaga przerwania timera mówi, czy okres był dłuższy od progu. Na czas bloku przerwania są wyłączone, ale ekran zostaje włączony. Linie tekstu są rysowane jako grafika trybu F, bo tekst w trybie ANTIC 2 zatrzymuje procesor na ~80 cykli i psułby pomiar.
- Szczegóły: komentarze w `tape_loader.asm` (tryb `TURBO`) i nagłówek `make_blizzard.py`.

---

## 10. Pliki w repo

| Plik | Rola |
|---|---|
| `make_tape.py` | główny skrypt: analiza XEX, kontrola pamięci, kompilacja loadera, budowa CAS |
| `tape_loader.asm` | uniwersalny loader BEKAPEKA (600 bodów i `TURBO`); kompiluje go `make_tape.py` |
| `make_blizzard.py` | XEX ↔ CAS Turbo Blizzard |
| `build_cas.py` | składanie i weryfikacja CAS 600 bodów |
| `xex_info.py` | stałe paska postępu |
| `logo_data.inc`, `gen_gfx.py`, `bekapeka_logo.png` | logo i teksty statusu (`python gen_gfx.py bekapeka_logo.png logo_data.inc`, wymaga Pillow) |
| `mads.exe`, `mads.pas`, `Mad-Assembler-2.1.6/` | assembler MADS z dokumentacją i przykładami |
| `run-xex.cmd` | uruchamia XEX w Altirze (popraw ścieżkę do Altirry w pliku) |
| `.claude/`, `CLAUDE.md` | skille i agenci Claude Code (`/atari-tape` robi kasety „na rozkaz”) |
| `riverraid_tape.asm`, `ninja_tape.asm`, `build*.cmd`, `bkpkloaderv2.asm` | starsze loadery robione osobno dla każdej gry |

Gier, gotowych kaset i loadera Blizzarda **nie ma w repo** (prawa autorskie).
