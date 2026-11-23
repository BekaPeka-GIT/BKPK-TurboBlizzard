# Raport z testów — kasety turbo z ekranem BEKAPEKA

Data: 2026-11-23. Emulator: Altirra 4.31 (XL PAL, 320K). Narzędzie: `make_tape.py --turbo`.

## Gry z katalogu `Gry-do-przerobienia`

| Gra | Kaseta | Wynik | Uwagi |
|---|---|---|---|
| Abracadabra | ok | gra startuje | zmienne loadera przeniesione na `$D6` (gra ładuje `$00D0-$00D5`) |
| Alley Cat | ok | logo + pasek, gra startuje | zmienne loadera na `$D6` |
| Arkanoid | ok | gra startuje | |
| Bruce Lee | ok | **zawiesza się** | patrz niżej |
| Da Fuzz | ok | logo + pasek, gra startuje | |
| Donkey Kong | ok | logo + pasek, gra startuje | zmienne loadera na `$D6` |
| Donkey Kong Junior | ok | logo + pasek, gra startuje | loader od `$0700` (gra zajmuje `$0600-$0615`); 1 B segmentu trafia w ROM `$C000` — pomijany jak przy DOS |
| Ghostbusters | **nie powstała** | — | 183 segmenty `$0B00-$BFFA`, brak miejsca na loader z ekranem; zostaje `make_blizzard.py` |
| Gyruss | ok | logo + pasek, gra startuje | |
| Mr Robot | ok | logo + pasek, gra startuje | |
| Pac-Man | ok | logo + pasek, gra startuje | segmenty `$D301`, `$D400` (rejestry) — ostrzeżenie |
| Pitfall II | ok | gra startuje | |
| Pitstop | ok | logo + pasek, gra startuje | |
| Pole Position | ok | gra startuje | |
| Popeye | ok | gra startuje | sprawdzony też z najnowszym loaderem |

„gra startuje” bez „logo” = zrzut z ekranem ładowania nie trafił w odpowiedni moment, gra wczytała się poprawnie.

### Bruce Lee

Segmenty: spakowane części + wspólny rozpakowywacz (`$0400`, `$0116-$01A3` na stronie stosu), 4 INIT-y; trzecia część rozpakowuje się m.in. w pamięć ekranu loadera (`$9E00-$B63F`). Ładowanie dochodzi do ok. 90%, potem obraz zastyga (tło loadera + paski intra AHT). Oryginalny XEX w Altirze działa.

Sprawdzone i odrzucone przyczyny (zmiany zostały w loaderze, bo są bezpieczne):

1. Zamazanie pamięci ekranu przez INIT → suma kontrolna ekranu przed/po INIT, ekran wygaszany do końca ładowania.
2. Śmieciowa Display List w trakcie INIT → na czas INIT pusta DL w kodzie loadera (`safedl`).
3. VBI intra nie woła systemowego (stoi `RTCLOK`) → czekanie na ramkę przez `VCOUNT`.

Dalszy krok: debugger Altirry w chwili zawieszenia (adres PC, stan NMIEN/VVBLK).

## Automatyczne rozmieszczanie (`make_tape.py`)

- `ZPB` — zmienne loadera na stronie zerowej: `$CE`, `$D6`, `$B0`, `$90`, `$80` (pierwsze wolne od segmentów gry).
- `LDRORG` — adres loadera: pierwsza wolna strona od `$0600` (rozmiar z kompilacji próbnej).
- Ekran — najniższa wolna granica 4 KB; w turbo bufor bloku + bitmapy (`EXT`, `$690` B) zaraz za ekranem albo osobno.
- Turbo: z zakazanych obszarów zostaje góra stosu `$01C0-$01FF`; ROM i rejestry `$D000-$D7FF` to ostrzeżenia (błąd tylko, gdy PORTB wyłącza ROM).

## Kartridż Phoenix 1.0

32 KB, typ Altirry 33 (Switchable XEGS). Menu: 1 TOS, 2 Micro TOS, 3 Phantom Copy 58 KB, 4 Universal Loader, 5 Binary File Loader, 6 Tape Doctor I, 7 Micro Loader v1.0 (KNS), dalsze pozycje niewidoczne.

| Test | Wynik |
|---|---|
| SELECT + START przy włączaniu, kaseta `pitstop_turbo.cas` | kartridż się wyłącza, boot kasety, **logo BEKAPEKA + pasek**, gra startuje |
| Opcja 5 + `Y`, oryginalna kaseta Blizzard (Spy's Demise) | gra działa; `make_blizzard.py` odtwarza tę kasetę bajt w bajt |
| Opcja 5 + `Y`, `riverraid_blizzard.cas` | nagłówek i dane wczytane, potem błąd programu (gra pod `$9FF0-$BFFF` = okno kartridża) |
| Opcja 5, `pitstop_turbo.cas` (z loaderem 600 bodów) | błąd programu — opcja 5 nie nadaje się do kaset z ekranem BEKAPEKA |
| Opcja 1 (TOS) | pyta o ramdysk `R:`, potem BASIC `READY` — kaseta z bootem nie ruszy |

Nie sprawdzono: opcje 2, 3, 4, 6, 7 jako loadery.

## Metoda testów

- Altirra z plikiem CAS (autoboot), zrzuty okna w zadanych sekundach (PowerShell).
- Przyspieszenie: F1 (Warp) trzymany po starcie bootu (od ok. 10. s); wciśnięty wcześniej potrafi zepsuć boot (Pole Position).
- Kartridż: obraz `.car` z nagłówkiem typu 33; klawisze konsoli (SELECT = F3, START = F2) trzymane przez `keybd_event`.
- Zrzuty: `zrzuty/` (lokalnie, poza repo — gry mają cudze prawa autorskie).

## Do zrobienia

- Bruce Lee — diagnoza w debuggerze Altirry.
- Przebudować kasety pozostałych gier najnowszym loaderem (`safedl`, `VCOUNT`) i przetestować ponownie (dotąd sprawdzony tylko Popeye).
- Test na prawdziwym sprzęcie (magnetofon, Phoenix).
