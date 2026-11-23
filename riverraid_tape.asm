; =====================================================================
; River Raid by BEKAPEKA - loader kasetowy z ekranem graficznym
; Atari 65XE, MADS
;
; Rekordy boot na kasecie. Po zaladowaniu przez system loader:
;   1. buduje ekran graficzny (wlasna Display List):
;        - tytul "RIVER RAID" (tryb ANTIC 7) i "BY BEKAPEKA" (tryb 6),
;        - logo BekaPeka (tryb F, 320x128, rozpakowane z RLE),
;        - linia statusu (tryb 2): procent, wczytane i pozostale bloki,
;        - pasek postepu (tryb F),
;   2. otwiera magnetofon (C:) i wczytuje plik XEX segment po segmencie,
;      porcjami po 128 B (jeden blok = jeden rekord kasety), po kazdej
;      porcji odswieza procenty, liczniki blokow i pasek,
;   3. zamyka kasete i uruchamia gre przez RUNAD.
;
; Wymaga plikow:  xex_info.inc  (python xex_info.py RiverRaid.xex xex_info.inc)
;                 gfx_data.inc  (python gen_gfx.py bekapeka_logo.png gfx_data.inc)
; Calosc buduje build.cmd. Wynik to surowy plik boot (opt h-).
; =====================================================================

        opt h-                  ; surowy plik, bez naglowka XEX

        icl 'xex_info.inc'      ; TOTALB, TOTBLK, SHIFT, UNITS

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
SDMCTL  = $022F
SDLSTL  = $0230
COLOR0  = $02C4
COLOR1  = $02C5
COLOR2  = $02C6
COLOR3  = $02C7
COLOR4  = $02C8
ATRACT  = $4D
PORTB   = $D301
PACTL   = $D302

; --- polecenia CIO ---
CMD_OPEN  = $03
CMD_GET   = $07
CMD_CLOSE = $0C
IOCB1     = $10                 ; kanal #1 (numer * 16)

; --- pamiec ekranu (poza obszarem gry $9FF0-$BFFF i poza loaderem) ---
STAT    = $3E00                 ; linia statusu, 40 B (tryb 2)
DL      = $3F00                 ; Display List (158 B, nie przekracza 1 KB)
LOGO    = $4060                 ; logo 128 linii x 40 B; linia 100 = $5000
BAR     = $5500                 ; pasek postepu, 8 linii x 40 B

; --- zmienne na stronie zerowej ---
src     = $CE                   ; wskaznik zrodla (2 B)
segst   = $D0                   ; poczatek segmentu (2 B)
segend  = $D2                   ; koniec segmentu (2 B)
dst     = $D4                   ; adres docelowy (2 B)
len     = $D6                   ; dlugosc (2 B)
stage   = $D8                   ; litera etapu (diagnostyka bledu)
done    = $D9                   ; wczytane bajty danych (2 B)
pct     = $DB                   ; procent 0..100
fill    = $DC                   ; narysowana szerokosc paska
chunk   = $DD                   ; rozmiar biezacej porcji
t1      = $DE
t2      = $DF
acc     = $E0                   ; (2 B)
lim     = $E2                   ; (2 B)
nfill   = $E4
d0      = $E5
d1      = $E6
d2      = $E7
blk     = $E8
ql      = $E9
qh      = $EA

        org $0600

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
        jsr setinit             ; INITAD = RTS

        lda #<msg_open
        ldx #>msg_open
        jsr settext             ; "OTWIERANIE KASETY..."

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
segloop lda #'H'-32
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

; --- koniec pliku: zamknij kasete i uruchom gre ---
finish  ldx #IOCB1
        lda #CMD_CLOSE
        sta ICCOM,x
        jsr CIOV
        lda #$3C
        sta PACTL               ; zatrzymaj magnetofon
        jmp (RUNAD)             ; start gry

; --- blad: pokaz kod statusu CIO i etap w linii statusu, zatrzymaj sie ---
error   tya
        pha
        lda #$3C
        sta PACTL
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
        jmp *

; =====================================================================
; Podprogramy kasety
; =====================================================================

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
        jsr callinit
        lda #$34
        sta PACTL
        jsr setinit
di_end  rts
callinit jmp (INITAD)

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
        lda #$9C
        sta COLOR0              ; jasnoniebieski ("RIVER")
        lda #$1C
        sta COLOR1              ; zloty (napisy, logo, pasek)
        lda #$10
        sta COLOR2              ; tlo trybow 2/F (czarne)
        lda #$0E
        sta COLOR3              ; bialy ("BY")
        lda #$10
        sta COLOR4              ; ramka i tlo trybow 6/7 (jak tlo trybow 2/F)
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
        jsr barinit
        lda #<tmpl
        ldx #>tmpl
        jsr settext
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
settext sta src
        stx src+1
        ldy #39
st1     lda (src),y
        sta STAT,y
        dey
        bpl st1
        rts

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
update  lda #0
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
        rts

; =====================================================================
; Dane
; =====================================================================
cname   dta c'C:',$9B
hexd    dta d'0123456789ABCDEF'
rts_vec rts

; opis Display Listy: pary (ile, wartosc), 0 = koniec; razem 186 linii
dlspec  dta 1,$70                       ; 8 pustych linii
        dta 1,$47,1,<title1,1,>title1   ; tryb 7 + LMS: "RIVER RAID"
        dta 1,$46,1,<title2,1,>title2   ; tryb 6 + LMS: "BY BEKAPEKA"
        dta 1,$30                       ; 4 puste linie
        dta 1,$4F,1,<LOGO,1,>LOGO       ; tryb F + LMS: logo, linia 0
        dta 99,$0F                      ; linie 1..99
        dta 1,$4F,1,<[LOGO+4000],1,>[LOGO+4000]  ; linia 100 = $5000 (granica 4 KB)
        dta 27,$0F                      ; linie 101..127
        dta 1,$30                       ; 4 puste linie
        dta 1,$42,1,<STAT,1,>STAT       ; tryb 2 + LMS: status
        dta 1,$10                       ; 2 puste linie
        dta 1,$4F,1,<BAR,1,>BAR         ; tryb F + LMS: pasek, linia 0
        dta 7,$0F                       ; linie 1..7
        dta 1,$41,1,<DL,1,>DL           ; JVB
        dta 0

        icl 'gfx_data.inc'      ; title1, title2, tmpl, msg_open, msg_err, logo_rle, OFS_*

ldr_end
