; =====================================================================
; Uniwersalny loader kasetowy BEKAPEKA z ekranem graficznym
; Atari XL/XE, MADS
;
; Nie kompiluj recznie - robi to make_tape.py (skill /atari-tape), ktory
; generuje dla kazdej gry dwa pliki w tape/<gra>/ i podaje je przez -i:
;   tape_cfg.inc   - TOTALB, TOTBLK, SHIFT, UNITS, SCR4K, TCOLOR, ANIM
;   tape_title.inc - etykieta gtitle: nazwa gry, 20 znakow trybu 7
; Wspolne dla wszystkich gier: logo_data.inc (python gen_gfx.py
; bekapeka_logo.png logo_data.inc).
;
; Rekordy boot na kasecie. Po zaladowaniu przez system loader:
;   1. buduje ekran graficzny (wlasna Display List):
;        - nazwa gry (tryb ANTIC 7) i "BY" (tryb 6),
;        - logo BekaPeka (tryb F, 320x128, rozpakowane z RLE),
;        - linia statusu (tryb 2): procent, wczytane i pozostale bloki,
;        - pasek postepu (tryb F),
;        - adres strony w prawym dolnym rogu (tryb 2),
;   2. otwiera magnetofon (C:) i wczytuje plik XEX segment po segmencie,
;      porcjami po 128 B (jeden blok = jeden rekord kasety), po kazdej
;      porcji odswieza procenty, liczniki blokow i pasek; po kazdym
;      INITAD przywraca swoj ekran (INIT gry moze go podmienic),
;   3. zamyka kasete i uruchamia gre przez RUNAD (albo gre uruchamia
;      ostatni INITAD, ktory nie wraca).
;
; ANIM = 1 (make_tape.py --anim): animacja logo w przerwaniach, dziala
; takze w trakcie odczytu kasety (VBI natychmiastowe + 2 DLI na klatke):
;   - ikona budynku podskakuje (wyskakuje w gore, zawisa, spada,
;     przysiada i odbija sie) - przesuwanie dwoch okien obrazu przez
;     adresy LMS w Display List,
;   - po skoku jasny pas przesuwa sie z gory na dol przez logo (odblask).
; Przed kazdym INIT/RUN gry animacja jest wylaczana (wektory przywrocone).
;
; TURBO = 1 (make_tape.py --turbo): gra nie jest nagrana rekordami 600 bodow,
; tylko w formacie Turbo Blizzard (bloki PWM, 1 KB danych na blok; patrz
; make_blizzard.py). Loader czyta je sam, przy WLACZONYM ekranie:
;   - bit = okres miedzy opadajacymi zboczami na linii danych SIO (SKSTAT
;     bit 4): 0 = 181 us, 1 = 272 us, pilot = 499 us,
;   - okres mierzy sprzet: kazde zbocze restartuje timery POKEY (kanaly 3+4,
;     16 bitow, 1,79 MHz), a bit 2 IRQST mowi, czy timer zdazyl dobiec do
;     zera (okres dluzszy niz prog). DMA ekranu opoznia tylko wykrycie
;     zbocza o kilkadziesiat cykli - prog lezy w polowie miedzy 0 i 1,
;   - na czas bloku NMI (VBI) i IRQ sa wylaczone, ANTIC dalej wyswietla
;     statyczny ekran (rejestry sprzetu ustawione przez ostatnie VBI).
; Gra trafia do bufora BUF (1 KB + 4), a stamtad przez getbyte do pamieci;
; po kazdym bloku odswiezany jest postep. TURBO wyklucza ANIM.
;
; Wynik to surowy plik boot (opt h-), ladowany pod LDRORG (domyslnie $0600).
; =====================================================================

        opt h-                  ; surowy plik, bez naglowka XEX

        icl 'tape_cfg.inc'      ; TOTALB, TOTBLK, SHIFT, UNITS, SCR4K, TCOLOR, ANIM, TURBO
        .ifndef TURBO
TURBO   = 0
        .endif
        .ifndef LDRORG
LDRORG  = $0600                 ; adres ladowania loadera (rekordy boot)
        .endif
        .ifndef ZPB
ZPB     = $CE                   ; poczatek zmiennych loadera na stronie zerowej
        .endif
        .ifndef EXT
EXT     = SCR4K+$640            ; TURBO: bufor bloku + bitmapy tekstu
        .endif
        .if TURBO&&ANIM
        .error "TURBO i ANIM naraz nie dzialaja (animacja wymaga VBI)"
        .endif

; --- adresy systemu operacyjnego ---
CIOV    = $E456
ICCOM   = $0342
ICBAL   = $0344
ICBAH   = $0345
ICBLL   = $0348
ICBLH   = $0349
ICAX1   = $034A
ICAX2   = $034B
RUNAD   = $02E0
INITAD  = $02E2
CH      = $02FC
CDTMV1  = $0218                 ; licznik systemowy 1 (timeout SIO)
ICHID   = $0340                 ; numer urzadzenia w IOCB, $FF = kanal zamkniety
SDMCTL  = $022F
SDLSTL  = $0230
COLOR0  = $02C4
COLOR1  = $02C5
COLOR2  = $02C6
COLOR3  = $02C7
COLOR4  = $02C8
CHBAS   = $02F4
GPRIOR  = $026F
ATRACT  = $4D
DMACTL  = $D400
DLISTL  = $D402
VCOUNT  = $D40B
PORTB   = $D301
PACTL   = $D302

; --- polecenia CIO ---
CMD_OPEN  = $03
CMD_GET   = $07
CMD_CLOSE = $0C
IOCB1     = $10                 ; kanal #1 (numer * 16)

; --- pamiec ekranu: blok SCR4K-$1200 .. SCR4K+$63F (SCR4K = granica 4 KB),
;     make_tape.py wybiera go tak, zeby nie nachodzil na segmenty gry ---
STAT    = SCR4K-$1200           ; linia statusu, 40 B (tryb 2)
DL      = SCR4K-$1100           ; Display List (~170 B, nie przekracza 1 KB)
LOGO    = SCR4K-4000            ; logo 128 linii x 40 B; linia 100 = SCR4K
BAR     = SCR4K+$500            ; pasek postepu, 8 linii x 40 B

        .if ANIM
; --- animacja: dwa okna ikony, kazde w osobnym bloku 4 KB (ANTIC nie
;     przekracza granicy 4 KB w obrebie okna); z nimi blok ekranu
;     siega do SCR4K+$2FEF ---
BUFA    = SCR4K+$1000           ; okno A (linie logo 0..51):   wiersze ikony -4..97
BUFB    = SCR4K+$2000           ; okno B (linie logo 52..103): wiersze ikony 48..149
ICOLS   = 98                    ; wiersze ikony kopiowane do okna A (0..97)
DL0     = 8                     ; przesuniecie instrukcji linii 0 logo w DL
DLA     = DL+DL0+1              ; adres LMS okna A (linia 0)
DLB     = DL+DL0+54+1           ; adres LMS okna B (linia 52)
JBEG    = 50                    ; klatka cyklu (0..255), w ktorej startuje skok
SHBEG   = 110                   ; klatka cyklu, w ktorej startuje odblask
SHLEN   = 60                    ; odblask trwa 60 klatek, pas schodzi o 2 linie/klatke
SHW     = 8                     ; wysokosc jasnego pasa (linie)
SHCOL   = $0F                   ; jasnosc pasa (tryb F: liczy sie luminancja COLPF1)
NRMCOL  = $1C                   ; zwykla jasnosc logo (= COLOR1)

COLPF1  = $D017
WSYNC   = $D40A
NMIEN   = $D40E
VDSLST  = $0200
VVBLKI  = $0222
SETVBV  = $E45C
        .endif

        .if TURBO
; --- odczyt turbo (Blizzard) ---
RTCLOK  = $12                   ; RTCLOK+2 zmienia sie co ramke (VBI)
POKMSK  = $10                   ; cien IRQEN
NMIEN_T = $D40E
AUDF3   = $D204
AUDC3   = $D205
AUDF4   = $D206
AUDC4   = $D207
AUDCTL  = $D208
STIMER  = $D209
IRQEN   = $D20E                 ; zapis
IRQST   = $D20E                 ; odczyt (bit = 0 -> przerwanie zgloszone)
SKCTL   = $D20F                 ; zapis
SKSTAT  = $D20F                 ; odczyt (bit 4 = linia danych SIO)
; progi = okres timera w cyklach 1,79 MHz minus 7 (tryb 16-bitowy)
; (szerokosc impulsu w CAS = caly okres: 0 = 8, 1 = 12, pilot = 22 probki 44,1 kHz;
;  sprawdzone w Altirze - prog 771 us nie widzial pilota)
TH_BIT  = 397                   ; ~227 us: srodek miedzy 0 (181 us) a 1 (272 us)
TH_PIL  = 679                   ; ~385 us: srodek miedzy 1 (272 us) a pilotem (499 us)
PILOTN  = 64                    ; tyle okresow pilota z rzedu = poczatek bloku
NAMELEN = 76                    ; naglowek Blizzarda: nazwa 76 znakow + suma
BLOCK   = 1024
; EXT: bufor bloku + bitmapy tekstu ($690 B), domyslnie zaraz za ekranem;
; make_tape.py moze go dac gdzie indziej, gdy tam jest gra
BUF     = EXT                   ; bufor bloku: dl. 2 B + 1024 B + 00 + suma
; Linie tekstu trybu 2 maja "zla linie" (40 kodow + 40 bajtow znakow w jednej
; linii), ktora zatrzymuje CPU na ~80 cykli - to psulo pomiar okresu.
; W TURBO status i adres strony sa bitmapami trybu F (8 x 40 B, litery z ROM).
STATBM  = EXT+$410               ; bitmapa linii statusu
WWWBM   = EXT+$550               ; bitmapa adresu strony (do EXT+$68F)
CHROM   = $E000                 ; zestaw znakow w ROM
        .endif

; --- zmienne na stronie zerowej: ZPB .. ZPB+$1C (TURBO: ZPB+$22); ZPB wybiera
;     make_tape.py tak, zeby nie nachodzily na segmenty gry (domyslnie $CE) ---
src     = ZPB+$00                   ; wskaznik zrodla (2 B)
segst   = ZPB+$02                   ; poczatek segmentu (2 B)
segend  = ZPB+$04                   ; koniec segmentu (2 B)
dst     = ZPB+$06                   ; adres docelowy (2 B)
len     = ZPB+$08                   ; dlugosc (2 B)
stage   = ZPB+$0A                   ; litera etapu (diagnostyka bledu)
done    = ZPB+$0B                   ; wczytane bajty danych (2 B)
pct     = ZPB+$0D                   ; procent 0..100
fill    = ZPB+$0E                   ; narysowana szerokosc paska
chunk   = ZPB+$0F                   ; rozmiar biezacej porcji
t1      = ZPB+$10
t2      = ZPB+$11
acc     = ZPB+$12                   ; (2 B)
lim     = ZPB+$14                   ; (2 B)
nfill   = ZPB+$16
d0      = ZPB+$17
d1      = ZPB+$18
d2      = ZPB+$19
blk     = ZPB+$1A
ql      = ZPB+$1B
qh      = ZPB+$1C
        .if TURBO
used    = ZPB+$1D                   ; bajty strumienia XEX oddane przez getbyte (2 B)
bleft   = ZPB+$1F                   ; bajty pozostale w buforze (2 B)
bptr    = ZPB+$21                   ; wskaznik w buforze (2 B)
; tblock dziala poza update, wiec pozycza jego zmienne:
tptr    = acc                   ; wskaznik zapisu (2 B)
tcnt    = lim                   ; licznik bajtow (2 B)
tlen    = ql                    ; dlugosc bloku z suma (ql, qh)
tbyte   = t1                    ; skladany bajt / licznik pilota / suma
        .endif

        org LDRORG

; --- naglowek rekordu boot (6 bajtow) ---
boot    dta 0                           ; flagi
        dta b([ldr_end-boot+127]/128)   ; liczba rekordow boot po 128 B
        dta a(boot)                     ; adres ladowania
        dta a(rts_vec)                  ; CASINI

; --- wejscie: system skacze tutaj (adres ladowania + 6) ---
start   lda #$3C
        sta PACTL               ; zatrzymaj magnetofon na czas przygotowan
        lda #$FF
        sta PORTB               ; wylacz BASIC
        jsr gfxinit             ; ekran graficzny
        .if ANIM
        jsr animon
        .endif
        jsr setinit             ; INITAD = RTS

        lda #<msg_open
        ldx #>msg_open
        jsr settext             ; "OTWIERANIE KASETY..."

        .if TURBO
; --- TURBO: blok 0 i naglowek Blizzarda, potem plik XEX z blokow 1 KB ---
        lda #0
        sta used
        sta used+1
        sta bleft
        sta bleft+1
        lda #$34
        sta PACTL               ; wlacz silnik magnetofonu
        lda #'T'-32
        sta stage
        lda #0                  ; blok 0: tylko dlugi pilot i sync - jego bajt 00
        tax                     ; nie ma zbocza konczacego (jak w Blizzardzie,
        jsr tblock              ; nie czytamy go)
        lda #'N'-32
        sta stage
        lda #<[NAMELEN+1]       ; naglowek: nazwa (pomijamy) + suma
        ldx #>[NAMELEN+1]
        jsr tblock

        lda #<tmpl
        ldx #>tmpl
        jsr settext             ; szablon linii postepu
        lda #TOTBLK
        ldx #OFS_TOT
        jsr prt3z               ; staly licznik: ile blokow lacznie
        jsr update              ; 0%

segloop jsr alldone             ; caly plik wczytany (np. ostatni INIT wrocil)?
        bne sl_rd
        jmp finish
sl_rd   lda #'H'-32
        sta stage
        jsr getbyte             ; poczatek segmentu (lub znacznik $FFFF)
        sta segst
        jsr getbyte
        sta segst+1
        and segst
        cmp #$FF
        beq segloop             ; znacznik $FFFF - czytaj naglowek jeszcze raz
        jsr getbyte             ; koniec segmentu
        sta segend
        jsr getbyte
        sta segend+1
        sec                     ; len = koniec - poczatek + 1
        lda segend
        sbc segst
        sta len
        lda segend+1
        sbc segst+1
        sta len+1
        inc len
        bne tl_ok
        inc len+1
tl_ok   lda segst
        sta dst
        lda segst+1
        sta dst+1
        lda #'D'-32
        sta stage
tdata   lda len                 ; dane segmentu bajt po bajcie z bufora
        ora len+1
        beq tdone
        jsr getbyte
        ldy #0
        sta (dst),y
        inc dst
        bne td1
        inc dst+1
td1     lda len
        bne td2
        dec len+1
td2     dec len
        jmp tdata
tdone   jsr doinit              ; INITAD, jesli segment go ustawil
        jmp segloop

        .else

; --- otwarcie magnetofonu (C:) do odczytu, tryb ciagly ---
        lda #'O'-32
        sta stage
        ldx #IOCB1
        lda #CMD_OPEN
        sta ICCOM,x
        lda #<cname
        sta ICBAL,x
        lda #>cname
        sta ICBAH,x
        lda #$04                ; tylko odczyt
        sta ICAX1,x
        lda #$80                ; tryb ciagly (krotkie przerwy IRG)
        sta ICAX2,x
        lda #$0C
        sta CH                  ; udawany klawisz RETURN - pomija "wcisnij PLAY"
        jsr CIOV
        lda #$FF
        sta CH                  ; kasuj "wcisniety klawisz"
        cpy #1
        beq opened
        jmp error

opened  lda #<tmpl
        ldx #>tmpl
        jsr settext             ; szablon linii postepu
        lda #TOTBLK
        ldx #OFS_TOT
        jsr prt3z                ; staly licznik: ile blokow lacznie
        jsr update              ; 0%

; --- petla segmentow pliku XEX ---
segloop jsr alldone             ; caly plik wczytany (np. ostatni INIT wrocil)?
        bne sl_rd
        jmp finish
sl_rd   lda #'H'-32
        sta stage
        lda #segst
        jsr rdw                 ; poczatek segmentu (lub znacznik $FFFF)
        cpy #$88                ; EOF w miejscu naglowka = koniec pliku
        bne hd1
        jmp finish
hd1
        cpy #1
        bne fail
        lda segst
        and segst+1
        cmp #$FF
        beq segloop             ; znacznik $FFFF - czytaj naglowek jeszcze raz
        lda #'E'-32
        sta stage
        lda #segend
        jsr rdw                 ; koniec segmentu
        cpy #1
        bne fail
        sec                     ; len = koniec - poczatek + 1
        lda segend
        sbc segst
        sta len
        lda segend+1
        sbc segst+1
        sta len+1
        inc len
        bne len_ok
        inc len+1
len_ok  lda segst
        sta dst
        lda segst+1
        sta dst+1
        lda #'D'-32
        sta stage

; --- dane segmentu: porcje po max. 128 B, po kazdej odswiezenie postepu ---
datalp  lda len
        ora len+1
        beq datadone
        lda len+1
        bne c128
        lda len
        cmp #129
        bcc csmall              ; len <= 128 -> porcja = len
c128    lda #128
csmall  sta chunk
        jsr rdchunk
        cpy #1
        bne fail
        clc                     ; dst += chunk
        lda dst
        adc chunk
        sta dst
        bcc dl1
        inc dst+1
dl1     sec                     ; len -= chunk
        lda len
        sbc chunk
        sta len
        bcs dl2
        dec len+1
dl2     clc                     ; done += chunk
        lda done
        adc chunk
        sta done
        bcc dl3
        inc done+1
dl3     jsr update              ; procenty, bloki, pasek
        jmp datalp
datadone
        jsr doinit              ; INITAD, jesli segment go ustawil
        jmp segloop
fail    jmp error
        .endif

; --- koniec pliku: zamknij kasete i uruchom gre ---
finish  jsr tclose
        .if ANIM
        jsr animoff
        .endif
        jmp (RUNAD)             ; start gry

; --- blad: pokaz kod statusu CIO i etap w linii statusu, zatrzymaj sie ---
error   tya
        pha
        lda #$3C
        sta PACTL
        lda hidden              ; ekran wylaczony (pamiec zajela gra):
        beq er_scr              ; blad = czerwone tlo
        lda #$34
        sta COLOR4
        jmp *
er_scr
        lda #<msg_err
        ldx #>msg_err
        jsr settext
        pla
        pha
        lsr
        lsr
        lsr
        lsr
        tax
        lda hexd,x
        sta STAT+OFS_EHEX
        pla
        and #$0F
        tax
        lda hexd,x
        sta STAT+OFS_EHEX+1
        lda stage
        sta STAT+OFS_ESTG
        .if TURBO
        jsr rstat
        .endif
        jmp *

; =====================================================================
; Podprogramy kasety
; =====================================================================

        .if TURBO
; getbyte: A = nastepny bajt strumienia XEX (pusty bufor -> nastepny blok)
getbyte lda bleft
        ora bleft+1
        bne gb_have
        jsr nextblk
gb_have ldy #0
        lda (bptr),y
        inc bptr
        bne gb1
        inc bptr+1
gb1     pha
        lda bleft
        bne gb2
        dec bleft+1
gb2     dec bleft
        inc used
        bne gb3
        inc used+1
gb3     pla
        rts

; nextblk: wczytaj blok danych (dl. 2 B, 1024 B, 00, suma), ustaw bufor
; i odswiez postep
nextblk lda #<[BLOCK+4]
        ldx #>[BLOCK+4]
        jsr tblock
        lda BUF                 ; liczba waznych bajtow w bloku
        sta bleft
        lda BUF+1
        sta bleft+1
        ora bleft
        bne nb_ok
        ldy #$88                ; blok pusty = koniec pliku, a dane mialy byc
        jmp error
nb_ok   lda #<[BUF+2]
        sta bptr
        lda #>[BUF+2]
        sta bptr+1
        clc                     ; done += dlugosc bloku
        lda done
        adc bleft
        sta done
        lda done+1
        adc bleft+1
        sta done+1
        jmp update

; tblock: wczytaj blok turbo - X:A bajtow (dane + suma) pod BUF, sprawdz sume.
; X:A = 0: tylko pilot i pierwszy impuls sync (blok 0).
; Blad: skok do error z Y = $8F (suma) albo $80 (BREAK).
tblock  sta tcnt
        sta tlen
        stx tcnt+1
        stx tlen+1
tb_vb   lda VCOUNT              ; poczekaj na VBI - cienie (DL, DMA, kolory)
        cmp #124                ; trafiaja do rejestrow sprzetu, potem VBI
        bcc tb_vb               ; bedzie wylaczone. Liczymy linie (VCOUNT),
tb_vb2  lda VCOUNT              ; nie RTCLOK: VBI gry (intro Bruce Lee)
        cmp #8                  ; moze nie wolac systemowego i RTCLOK stoi
        bcs tb_vb2
        lda #0
        sta NMIEN_T             ; bez VBI/DLI - ekran dalej wyswietlany
        sta IRQEN
        sta AUDC3               ; timery bez dzwieku
        sta AUDC4
        sei
        lda #$83
        sta SKCTL               ; jak Blizzard
        lda #$28                ; kanal 3 z 1,79 MHz, kanaly 3+4 jako 16 bitow
        sta AUDCTL
        lda #<TH_PIL
        sta AUDF3
        lda #>TH_PIL
        sta AUDF4
        ldx #$84                ; X i Y stale w edge: IRQEN = timer 4 + BREAK
        ldy #0
tb_p0   lda #PILOTN             ; pilot: PILOTN dlugich okresow z rzedu
        sta tbyte
tb_p1   jsr edge
        bne tb_p0               ; krotki okres - liczymy od nowa
        dec tbyte
        bne tb_p1
tb_s1   jsr edge
        beq tb_s1               ; reszta pilota, az do pierwszego impulsu sync
        lda tlen
        ora tlen+1
        bne tb_dat
        jmp tend                ; dlugosc 0: sam pilot (blok 0)
tb_dat  lda #<TH_BIT            ; prog bitow zadziala od nastepnego STIMER
        sta AUDF3
        lda #>TH_BIT
        sta AUDF4
        jsr edge                ; drugi impuls sync
        lda #<BUF
        sta tptr
        lda #>BUF
        sta tptr+1
tb_byte lda #1                  ; znacznik: po 8 bitach wypadnie do C
        sta tbyte
tb_bit  jsr edge
        clc
        bne tb_0                ; krotki okres = 0
        sec                     ; dlugi okres = 1 (najstarszy bit pierwszy)
tb_0    rol tbyte
        bcc tb_bit
        lda tbyte
        sta (tptr),y
        inc tptr
        bne tb_1
        inc tptr+1
tb_1    lda tcnt
        bne tb_2
        dec tcnt+1
tb_2    dec tcnt
        lda tcnt
        ora tcnt+1
        bne tb_byte
        jsr tend
; suma: (tlen - 1) bajtow mod 256 = ostatni bajt bloku
        lda #<BUF
        sta tptr
        lda #>BUF
        sta tptr+1
        sec
        lda tlen
        sbc #1
        sta tcnt
        lda tlen+1
        sbc #0
        sta tcnt+1
        lda #0
        sta tbyte
        ldy #0
tc_lp   lda tcnt
        ora tcnt+1
        beq tc_end
        clc
        lda tbyte
        adc (tptr),y
        sta tbyte
        inc tptr
        bne tc_1
        inc tptr+1
tc_1    lda tcnt
        bne tc_2
        dec tcnt+1
tc_2    dec tcnt
        jmp tc_lp
tc_end  lda (tptr),y
        cmp tbyte
        bne tc_bad
        rts
tc_bad  ldy #$8F                ; zla suma kontrolna (jak blad CIO 143)
        jmp error

; edge: czekaj na opadajace zbocze, zrestartuj timery. Z = 1, gdy okres od
; poprzedniego zbocza byl dluzszy niz prog (timer 4 zdazyl dobiec do zera).
; Wymaga X = $84, Y = 0. Petla ed_lo musi byc krotka (dokladnosc pomiaru).
edge    lda #$10
ed_hi   bit IRQST               ; BREAK (bit 7 = 0)?
        bpl ed_brk
        bit SKSTAT
        beq ed_hi               ; czekaj na stan wysoki
ed_lo   bit SKSTAT
        bne ed_lo               ; czekaj na zbocze opadajace
        stx STIMER              ; restart timerow
        lda IRQST               ; stan z mijajacego okresu
        sty IRQEN               ; skasuj flagi...
        stx IRQEN               ; ...i uzbroj od nowa
        bpl ed_brk
        and #$04
        rts
ed_brk  jsr tend
        ldy #$80                ; BREAK (jak blad CIO 128)
        jmp error

; tend: przywroc przerwania i POKEY po bloku turbo
tend    lda #0
        sta IRQEN
        sta AUDCTL
        lda #$40
        sta NMIEN_T             ; VBI
        lda POKMSK
        sta IRQEN
        cli
        lda #$03
        sta SKCTL
        rts
        .else

; rdw: czytaj 2 bajty z kasety do zmiennej na stronie zerowej (adres w A)
rdw     sta dst
        lda #0
        sta dst+1
        sta len+1
        lda #2
        sta len
; rdblk: czytaj len bajtow z kasety pod adres dst; zwraca Y = status CIO
rdblk   ldx #IOCB1
        lda dst
        sta ICBAL,x
        lda dst+1
        sta ICBAH,x
        lda len
        sta ICBLL,x
        lda len+1
        sta ICBLH,x
        lda #CMD_GET
        sta ICCOM,x
        jmp CIOV

; rdchunk: czytaj chunk bajtow (max 128) pod adres dst; zwraca Y = status CIO
rdchunk ldx #IOCB1
        lda dst
        sta ICBAL,x
        lda dst+1
        sta ICBAH,x
        lda chunk
        sta ICBLL,x
        lda #0
        sta ICBLH,x
        lda #CMD_GET
        sta ICCOM,x
        jmp CIOV
        .endif

; doinit: wywolaj INITAD, jesli segment go zmienil. Kaseta stoi na czas
; inicjalizacji, zeby nie przegapic kolejnego rekordu.
doinit  lda INITAD
        cmp #<rts_vec
        bne di_run
        lda INITAD+1
        cmp #>rts_vec
        beq di_end
di_run  lda #$3C
        sta PACTL
        jsr alldone             ; ostatni INIT czesto nie wraca (Ninja startuje
        bne di_go               ; z niego gre) - oddaj mu system jak po DOS
        jsr tclose
di_go
        .if ANIM
        jsr animoff             ; INIT gry dostaje system bez naszych przerwan
        .endif
        jsr scrsum              ; suma pamieci ekranu przed INIT
        lda lim
        sta ssum
        lda lim+1
        sta ssum+1
        lda #<safedl            ; na czas INIT: pusta Display List w kodzie loadera -
        sta SDLSTL              ; INIT moze rozpakowac dane w pamiec ekranu (Bruce Lee)
        sta DLISTL              ; i ANTIC nie moze wtedy czytac smieci jako DL
        lda #>safedl
        sta SDLSTL+1
        sta DLISTL+1
        jsr callinit
        jsr scrsum              ; INIT zmienil pamiec ekranu (np. rozpakowal tam
        lda lim                 ; dane gry, jak Bruce Lee)? - wtedy ekran zostaje
        cmp ssum                ; wylaczony do konca, a loader juz nic nie rysuje
        bne di_hid
        lda lim+1
        cmp ssum+1
        beq di_ok
di_hid  lda #1
        sta hidden
di_ok   jsr scron               ; INIT gry mogl podmienic Display List i kolory
        .if ANIM
        lda hidden
        bne di_na
        jsr animon
di_na
        .endif
        lda #$34
        sta PACTL
        jsr setinit
di_end  rts
callinit jmp (INITAD)

; scrsum: 16-bitowa suma bajtow bloku ekranu SCR4K-$1200 .. SCR4K+$63F -> lim
SCRLEN  = $1840
scrsum  lda #<[SCR4K-$1200]
        sta acc
        lda #>[SCR4K-$1200]
        sta acc+1
        ldy #0
        sty lim
        sty lim+1
        ldx #>SCRLEN            ; pelne strony
ss_lp   clc
        lda lim
        adc (acc),y
        sta lim
        bcc ss_1
        inc lim+1
ss_1    iny
        bne ss_lp
        inc acc+1
        dex
        bne ss_lp
ss_rest clc                     ; reszta <SCRLEN bajtow
        lda lim
        adc (acc),y
        sta lim
        bcc ss_2
        inc lim+1
ss_2    iny
        cpy #<SCRLEN
        bne ss_rest
        rts
        ert <SCRLEN=0
ssum    dta a(0)                ; suma ekranu przed INIT
safedl  dta $70,$70,$41,a(safedl)  ; pusta DL: 16 pustych linii + JVB
        ert [safedl&$FC00]<>[[safedl+4]&$FC00]
hidden  dta 0                   ; 1 = gra zajela pamiec ekranu: ekran wylaczony

; alldone: Z = 1, gdy wczytano wszystkie bajty danych (done = TOTALB);
; TURBO: gdy getbyte oddal caly strumien XEX (used = TOTALB)
alldone
        .if TURBO
        lda used
        cmp #<TOTALB
        bne ad_end
        lda used+1
        .else
        lda done
        cmp #<TOTALB
        bne ad_end
        lda done+1
        .endif
        cmp #>TOTALB
ad_end  rts

; tclose: przed oddaniem sterowania grze (ostatni INIT albo RUNAD):
; - wylacz ekran, poki nasza Display List jest cala i bez bitow DLI.
;   Gra zwykle nadpisuje DL loadera; ANTIC z wylaczonym DMA powtarza
;   ostatnia pobrana instrukcje - smieciowa z bitem DLI dawala DLI w kazdej
;   linii, VBI zawsze trafialo w DLI (flaga I) i OS XL pomijal odroczone
;   VBI gry (Ninja: kolorowe pasy zamiast gry),
; - zamknij kasete (jesli otwarta), zatrzymaj silnik i skasuj licznik
;   timeoutu SIO
tclose  lda #0
        sta SDMCTL
        sta DMACTL
        .if TURBO               ; turbo nie otwiera C: - tylko silnik i licznik
        jmp tc_off
        .endif
        ldx #IOCB1
        lda ICHID,x
        cmp #$FF
        beq tc_off
        lda #CMD_CLOSE
        sta ICCOM,x
        jsr CIOV
tc_off  lda #$3C
        sta PACTL               ; zatrzymaj magnetofon
        lda #0
        sta CDTMV1
        sta CDTMV1+1
        rts

setinit lda #<rts_vec
        sta INITAD
        lda #>rts_vec
        sta INITAD+1
        rts

; =====================================================================
; Grafika
; =====================================================================

; gfxinit: Display List, logo, pasek, kolory; wlacza ekran
gfxinit lda #0
        sta done
        sta done+1
        sta pct
        sta fill
        lda #<dlspec            ; Display List z opisu (pary ile, wartosc)
        sta src
        lda #>dlspec
        sta src+1
        lda #<DL
        sta dst
        lda #>DL
        sta dst+1
        jsr rleout
        lda #<logo_rle          ; logo -> pamiec ekranu
        sta src
        lda #>logo_rle
        sta src+1
        lda #<LOGO
        sta dst
        lda #>LOGO
        sta dst+1
        jsr rleout
        jsr undelta             ; odwroc delte pionowa (linia XOR poprzednia)
        .if ANIM
        jsr bufinit             ; okna ikony do animacji
        .endif
        jsr barinit
        .if TURBO
        lda #<www               ; adres strony -> bitmapa (raz)
        sta src
        lda #>www
        sta src+1
        lda #<WWWBM
        sta lim
        lda #>WWWBM
        sta lim+1
        jsr rtext
        .endif
        lda #<tmpl
        ldx #>tmpl
        jsr settext
; scron: kolory i Display List loadera, wlacza ekran (tez po INIT gry)
scron   lda hidden
        beq sc_on
        lda #0                  ; pamiec ekranu nalezy do gry - nie pokazuj jej
        sta SDMCTL
        rts
sc_on   lda #TCOLOR
        sta COLOR0              ; kolor nazwy gry (z tape_cfg.inc)
        lda #$1C
        sta COLOR1              ; zloty (napisy, logo, pasek)
        lda #$10
        sta COLOR2              ; tlo trybow 2/F (czarne)
        lda #$0E
        sta COLOR3              ; bialy ("BY")
        lda #$10
        sta COLOR4              ; ramka i tlo trybow 6/7 (jak tlo trybow 2/F)
        lda #$E0
        sta CHBAS               ; zestaw znakow z ROM (INIT gry mogl go zmienic)
        lda #0
        sta GPRIOR              ; zwykle priorytety i kolory trybow
        lda #<DL                ; wlacz ekran
        sta SDLSTL
        lda #>DL
        sta SDLSTL+1
        lda #$22
        sta SDMCTL
        rts

; rleout: rozpakuj pary (ile, wartosc) z (src) pod (dst); ile = 0 konczy
rleout  ldy #0
rl1     lda (src),y
        beq rldone
        tax
        inc src
        bne rl2
        inc src+1
rl2     lda (src),y
        inc src
        bne rl3
        inc src+1
rl3     sta (dst),y
        inc dst
        bne rl4
        inc dst+1
rl4     dex
        bne rl3
        beq rl1
rldone  rts

; undelta: kazda linia logo XOR poprzednia (od linii 1 w gore)
undelta lda #<LOGO
        sta src
        lda #>LOGO
        sta src+1
        lda #<[LOGO+40]
        sta dst
        lda #>[LOGO+40]
        sta dst+1
        lda #<5080              ; 127 linii * 40 B
        sta len
        lda #>5080
        sta len+1
ud1     ldy #0
        lda (dst),y
        eor (src),y
        sta (dst),y
        inc dst
        bne ud2
        inc dst+1
ud2     inc src
        bne ud3
        inc src+1
ud3     lda len
        bne ud4
        dec len+1
ud4     dec len
        lda len
        ora len+1
        bne ud1
        rts

; barinit: czysci pasek i rysuje ramke (gora, dol, boki)
barinit ldx #0
        lda #0
bi1     sta BAR,x
        sta BAR+256,x
        inx
        bne bi1
        ldx #39
        lda #$FF
bi2     sta BAR,x               ; linia 0
        sta BAR+280,x           ; linia 7
        dex
        bpl bi2
        lda #$80                ; lewa krawedz, linie 1..6
        sta BAR+40
        sta BAR+80
        sta BAR+120
        sta BAR+160
        sta BAR+200
        sta BAR+240
        lda #$01                ; prawa krawedz, linie 1..6
        sta BAR+79
        sta BAR+119
        sta BAR+159
        sta BAR+199
        sta BAR+239
        sta BAR+279
        rts

; settext: skopiuj 40 B z (A=lo, X=hi) do linii statusu
settext ldy hidden              ; pamiec ekranu nalezy do gry - nie pisz
        bne st_x
        sta src
        stx src+1
        ldy #39
st1     lda (src),y
        sta STAT,y
        dey
        bpl st1
        .if TURBO
        jmp rstat
        .endif
st_x    rts

        .if TURBO
; rstat: linia statusu (STAT, kody ekranowe) -> bitmapa STATBM
rstat   lda hidden
        beq rs_go
        rts
rs_go   lda #<STAT
        sta src
        lda #>STAT
        sta src+1
        lda #<STATBM
        sta lim
        lda #>STATBM
        sta lim+1
; rtext: 40 kodow ekranowych z (src) -> bitmapa trybu F 8 x 40 B pod (lim),
; ksztalty liter z ROM. Niszczy acc, lim, t1, t2 (nie dst/len - wolane
; takze w trakcie kopiowania segmentu, z update).
rtext   lda #0
        sta t1                  ; wiersz znaku 0..7
rt_row  ldy #0                  ; kolumna 0..39
rt_col  lda (src),y
        and #$7F                ; bez inwersu
        sta acc                 ; acc = CHROM + kod*8 + wiersz
        lda #0
        asl acc
        rol
        asl acc
        rol
        asl acc
        rol
        ora #>CHROM
        sta acc+1
        lda acc
        ora t1
        sta acc
        ldx #0
        lda (acc,x)
        sta (lim),y
        iny
        cpy #40
        bne rt_col
        clc                     ; nastepny wiersz bitmapy
        lda lim
        adc #40
        sta lim
        bcc rt_1
        inc lim+1
rt_1    inc t1
        lda t1
        cmp #8
        bne rt_row
        rts
        .endif

; digits: A (0..255) -> d2 (setki), d1 (dziesiatki), d0 (jednosci)
digits  ldy #0
dg1     cmp #100
        bcc dg2
        sbc #100
        iny
        bne dg1
dg2     sty d2
        ldy #0
dg3     cmp #10
        bcc dg4
        sbc #10
        iny
        bne dg3
dg4     sty d1
        sta d0
        rts

; prt3: wpisz A (0..255) jako 3 cyfry bez zer wiodacych do STAT+X
prt3    jsr digits
        lda d2
        beq p3e
        ora #16                 ; kod ekranowy cyfry '0' = 16
p3e     sta STAT,x
        inx
        lda d2
        ora d1
        beq p3f
        lda d1
        ora #16
p3f     sta STAT,x
        inx
        lda d0
        ora #16
        sta STAT,x
        rts

; prt3z: wpisz A (0..255) jako 3 cyfry z zerami wiodacymi do STAT+X
prt3z   jsr digits
        lda d2
        ora #16
        sta STAT,x
        inx
        lda d1
        ora #16
        sta STAT,x
        inx
        lda d0
        ora #16
        sta STAT,x
        rts
; update: przelicz procent / bloki z 'done', odswiez status i pasek
update  lda hidden              ; pamiec ekranu nalezy do gry - nie rysuj
        beq up_go
        rts
up_go   lda #0
        sta ATRACT              ; bez trybu "attract" (przyciemniania)
        lda done                ; q = done >> SHIFT
        sta ql
        lda done+1
        sta qh
        ldx #SHIFT
u_sh    lsr qh
        ror ql
        dex
        bne u_sh
        lda #0                  ; acc = q * 100
        sta acc
        sta acc+1
u_mul   lda ql
        ora qh
        beq u_muld
        clc
        lda acc
        adc #100
        sta acc
        bcc u_m1
        inc acc+1
u_m1    lda ql
        bne u_m2
        dec qh
u_m2    dec ql
        jmp u_mul
u_muld  lda #0                  ; pct = acc / UNITS
        sta pct
u_div   lda acc+1
        cmp #>UNITS
        bcc u_divd
        bne u_dsub
        lda acc
        cmp #<UNITS
        bcc u_divd
u_dsub  sec
        lda acc
        sbc #<UNITS
        sta acc
        lda acc+1
        sbc #>UNITS
        sta acc+1
        inc pct
        jmp u_div
u_divd  lda pct
        ldx #OFS_PCT
        jsr prt3
        .if TURBO
        clc                     ; blk = (done + 1023) >> 10 (bloki po 1 KB)
        lda done
        adc #<1023
        lda done+1
        adc #>1023
        lsr
        lsr
        sta blk
        .else
        clc                     ; blk = (done + 127) >> 7
        lda done
        adc #127
        sta t1
        lda done+1
        adc #0
        sta t2
        lda t1
        asl
        lda t2
        rol
        sta blk
        .endif
        ldx #OFS_BLK
        jsr prt3z
        sec                     ; pozostalo = TOTBLK - blk
        lda #TOTBLK
        sbc blk
        bcs u_rem
        lda #0
u_rem   ldx #OFS_REM
        jsr prt3z
        lda #0                  ; lim = pct * 38
        sta lim
        sta lim+1
        ldx pct
        beq u_limd
u_lim   clc
        lda lim
        adc #38
        sta lim
        bcc u_l1
        inc lim+1
u_l1    dex
        bne u_lim
u_limd  ldy #0                  ; nfill = lim / 100
        lda #100
        sta acc
        lda #0
        sta acc+1
u_f     lda lim+1
        cmp acc+1
        bcc u_fd
        bne u_fy
        lda lim
        cmp acc
        bcc u_fd
u_fy    iny
        clc
        lda acc
        adc #100
        sta acc
        bcc u_f
        inc acc+1
        jmp u_f
u_fd    sty nfill
        ldx fill                ; dorysuj kolumny fill+1 .. nfill
u_bd    cpx nfill
        bcs u_bdd
        inx
        lda #$FF
        sta BAR+40,x
        sta BAR+80,x
        sta BAR+120,x
        sta BAR+160,x
        sta BAR+200,x
        sta BAR+240,x
        jmp u_bd
u_bdd   lda nfill
        sta fill
        .if TURBO
        jmp rstat               ; procenty i liczniki -> bitmapa statusu
        .else
        rts
        .endif

; =====================================================================
; Dane
; =====================================================================
cname   dta c'C:',$9B
hexd    dta d'0123456789ABCDEF'
rts_vec rts

; opis Display Listy: pary (ile, wartosc), 0 = koniec; razem 198 linii
dlspec  dta 1,$70                       ; 8 pustych linii
        dta 1,$47,1,<gtitle,1,>gtitle   ; tryb 7 + LMS: nazwa gry
        dta 1,$46,1,<byline,1,>byline   ; tryb 6 + LMS: "BY"
        dta 1,$30                       ; 4 puste linie
        .if ANIM
        dta 1,$4F,1,<[BUFA+160],1,>[BUFA+160]  ; linia 0: okno A (LMS zmienia VBI)
        dta 51,$0F                      ; linie 1..51
        dta 1,$4F,1,<[BUFB+160],1,>[BUFB+160]  ; linia 52: okno B (LMS zmienia VBI)
        dta 51,$0F                      ; linie 53..103
        dta 1,$4F,1,<[LOGO+4160],1,>[LOGO+4160]  ; linia 104: napis, nieruchomy
        dta 23,$0F                      ; linie 105..127
        .else
        dta 1,$4F,1,<LOGO,1,>LOGO       ; tryb F + LMS: logo, linia 0
        dta 99,$0F                      ; linie 1..99
        dta 1,$4F,1,<[LOGO+4000],1,>[LOGO+4000]  ; linia 100 = SCR4K (granica 4 KB)
        dta 27,$0F                      ; linie 101..127
        .endif
        dta 1,$30                       ; 4 puste linie
        .if TURBO
        dta 1,$4F,1,<STATBM,1,>STATBM   ; tryb F + LMS: status jako bitmapa
        dta 7,$0F
        .else
        dta 1,$42,1,<STAT,1,>STAT       ; tryb 2 + LMS: status
        .endif
        dta 1,$10                       ; 2 puste linie
        dta 1,$4F,1,<BAR,1,>BAR         ; tryb F + LMS: pasek, linia 0
        dta 7,$0F                       ; linie 1..7
        dta 1,$30                       ; 4 puste linie
        .if TURBO
        dta 1,$4F,1,<WWWBM,1,>WWWBM     ; tryb F + LMS: adres strony jako bitmapa
        dta 7,$0F
        .else
        dta 1,$42,1,<www,1,>www         ; tryb 2 + LMS: adres strony
        .endif
        dta 1,$41,1,<DL,1,>DL           ; JVB
        dta 0

; "BY" w trybie 6 (20 znakow), kolor COLOR3 (bity 6-7 = 11): 'B'=$22, 'Y'=$39
byline  dta d'         '
        dta $22|$C0,$39|$C0
        dta d'         '
; adres strony w trybie 2 (40 znakow), wyrownany do prawej
www     dta d'                    https://bekapeka.org'

        .if ANIM
; =====================================================================
; Animacja logo (ANIM = 1)
; =====================================================================

; bufinit: okna ikony. Przy przesunieciu v (= wysokosc skoku + 4) okno A
; pokazuje wiersze ikony v-4 .. v+47, okno B wiersze v+48 .. v+99.
; Poza ikona (wiersze < 0 i > 103) okna sa puste.
bufinit lda #<BUFA              ; wyczysc oba okna (BUFA .. BUFB+$FFF)
        sta dst
        lda #>BUFA
        sta dst+1
        ldx #$20                ; 32 strony
        lda #0
        tay
bf_clr  sta (dst),y
        iny
        bne bf_clr
        inc dst+1
        dex
        bne bf_clr
        lda #<LOGO              ; okno A od wiersza 4: wiersze ikony 0..97
        sta src
        lda #>LOGO
        sta src+1
        lda #<[BUFA+160]
        sta dst
        lda #>[BUFA+160]
        sta dst+1
        lda #<[ICOLS*40]
        sta len
        lda #>[ICOLS*40]
        sta len+1
        jsr copy
        lda #<[LOGO+48*40]      ; okno B od wiersza 0: wiersze ikony 48..103
        sta src
        lda #>[LOGO+48*40]
        sta src+1
        lda #<BUFB
        sta dst
        lda #>BUFB
        sta dst+1
        lda #<[56*40]
        sta len
        lda #>[56*40]
        sta len+1
; copy: kopiuj len (> 0) bajtow z (src) pod (dst)
copy    ldy #0
cp_lp   lda (src),y
        sta (dst),y
        inc src
        bne cp_1
        inc src+1
cp_1    inc dst
        bne cp_2
        inc dst+1
cp_2    lda len
        bne cp_3
        dec len+1
cp_3    dec len
        lda len
        ora len+1
        bne cp_lp
        rts

; animon: zapamietaj biezace wektory VVBLKI i VDSLST (system albo te,
; ktore ustawil INIT gry), wlacz VBI animacji i DLI odblasku
animon  lda VVBLKI
        sta oldvbi
        lda VVBLKI+1
        sta oldvbi+1
        lda VDSLST
        sta olddli
        lda VDSLST+1
        sta olddli+1
        ldy #<vbi
        ldx #>vbi
        lda #6                  ; VBI natychmiastowe - dziala tez przy CRITIC (SIO)
        jsr SETVBV
        lda #<dli
        sta VDSLST
        lda #>dli
        sta VDSLST+1
        lda #$C0                ; DLI + VBI
        sta NMIEN
        rts

; animoff: przywroc wektory VBI i DLI sprzed animon, wylacz DLI,
; ustaw okna ikony w spoczynku i skasuj bity DLI w DL
animoff ldy oldvbi
        ldx oldvbi+1
        lda #6
        jsr SETVBV
        lda #$40                ; tylko VBI
        sta NMIEN
        lda olddli              ; DLI juz wylaczone - mozna zmienic wektor
        sta VDSLST
        lda olddli+1
        sta VDSLST+1
        lda #<[4*40]            ; okna w spoczynku (v = 4)
        sta DLA
        sta DLB
        lda #>BUFA
        sta DLA+1
        lda #>BUFB
        sta DLB+1
; dlclr: skasuj bity DLI ustawione w poprzedniej klatce
dlclr   ldy dlio1
        lda DL,y
        and #$7F
        sta DL,y
        ldy dlio2
        lda DL,y
        and #$7F
        sta DL,y
        lda #0                  ; przesuniecie 0 = instrukcja $70, bez skutku
        sta dlio1
        sta dlio2
        rts

; vbi: jedna klatka animacji (cykl 256 klatek), potem VBI poprzednie.
; Krotkie (ok. 300 cykli), zeby nie zaburzac odczytu kasety.
vbi     lda #$C0                ; DLI + VBI - na wypadek, gdyby ktos wylaczyl DLI
        sta NMIEN
        inc tick
        lda tick
        sec
        sbc #JBEG
        cmp #JLEN
        bcc v_jump
        lda #<[4*40]            ; spoczynek: v = 4
        ldx #>[4*40]
        jmp v_lms
v_jump  tay
        lda jlo,y
        ldx jhi,y
v_lms   sta DLA                 ; okna wyrownane do 4 KB: mlodszy bajt = przesuniecie
        sta DLB
        txa
        clc
        adc #>BUFA
        sta DLA+1
        txa
        clc
        adc #>BUFB
        sta DLB+1

        jsr dlclr
        lda tick                ; odblask: pas od linii 2k+1 do 2k+SHW
        sec
        sbc #SHBEG
        cmp #SHLEN
        bcs v_end
        asl
        pha
        jsr lnoff
        sty dlio1
        pla
        clc
        adc #SHW
        jsr lnoff
        sty dlio2
        ldy dlio1
        lda DL,y
        ora #$80
        sta DL,y
        ldy dlio2
        lda DL,y
        ora #$80
        sta DL,y
        lda #SHCOL
        sta shv
v_end   jmp (oldvbi)

; lnoff: A = linia logo (0..127) -> Y = przesuniecie jej instrukcji w DL
; (linie 0, 52 i 104 maja LMS, czyli instrukcje 3-bajtowe)
lnoff   tay
        clc
        adc #DL0
        cpy #1
        bcc lo_end
        adc #1                  ; C = 1, wiec +2
        cpy #53
        bcc lo_end
        adc #1
        cpy #105
        bcc lo_end
        adc #1
lo_end  tay
        rts

; dli: pierwsze DLI w klatce rozjasnia logo, drugie przywraca jasnosc
dli     pha
        lda shv
        sta WSYNC
        sta COLPF1
        lda #NRMCOL
        sta shv
        pla
        rti

tick    dta 0                   ; licznik klatek cyklu
shv     dta NRMCOL              ; kolor dla nastepnego DLI
dlio1   dta 0                   ; przesuniecia instrukcji DL z bitem DLI
dlio2   dta 0
oldvbi  dta a(0)                ; wektor VVBLKI sprzed animon
olddli  dta a(0)                ; wektor VDSLST sprzed animon
        ert <oldvbi=$FF         ; jmp (oldvbi) nie moze lezec na granicy strony

; skok: przesuniecie okien v*40 w kolejnych klatkach, v = wysokosc + 4
; (wzlot 18 klatek, zawis, spadek 16, przysiad, male odbicie)
jlo     dta $68,$30,$D0,$70,$10,$B0,$28,$A0,$F0,$68,$B8,$08,$30,$80,$A8,$A8,$D0,$D0,$D0
        dta $D0,$D0,$D0,$A8,$80,$58,$30,$E0,$68,$F0,$78,$00,$60,$C0,$20,$58,$90,$A0
        dta $00,$00,$28,$50,$78,$A0,$F0,$40,$90,$B8,$B8,$B8,$90,$40,$F0,$50,$78,$A0
jhi     dta $01,$02,$02,$03,$04,$04,$05,$05,$05,$06,$06,$07,$07,$07,$07,$07,$07,$07,$07
        dta $07,$07,$07,$07,$07,$07,$07,$06,$06,$05,$05,$05,$04,$03,$03,$02,$01,$00
        dta $00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00
jend
JLEN    = jhi-jlo
        ert jend-jhi<>JLEN      ; tablice jlo i jhi musza miec rowna dlugosc
        .endif

        icl 'tape_title.inc'    ; gtitle - nazwa gry (generuje make_tape.py)
        icl 'logo_data.inc'     ; tmpl, msg_open, msg_err, logo_rle, OFS_*

; linie pokazywane przez ANTIC wprost z loadera nie moga przekraczac granicy 4 KB
        ert [gtitle&$F000]<>[[gtitle+19]&$F000]
        ert [byline&$F000]<>[[byline+19]&$F000]
        ert [www&$F000]<>[[www+39]&$F000]
        .if TURBO
        ert [STATBM&$F000]<>[[STATBM+319]&$F000]   ; bitmapy tez nie moga
        ert [WWWBM&$F000]<>[[WWWBM+319]&$F000]     ; przekraczac granicy 4 KB
        .endif
        ert ZPB+$22>$FF                            ; zmienne loadera na stronie zerowej

ldr_end
