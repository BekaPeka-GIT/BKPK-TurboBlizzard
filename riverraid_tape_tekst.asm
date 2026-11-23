; =====================================================================
; River Raid - loader kasetowy dla Atari 65XE (MADS)
;
; Ten kod jest zapisany w rekordach boot na kasecie. System ładuje go
; sam (START przy włączaniu komputera), a potem skacze pod adres
; ładowania + 6. Loader:
;   1. zatrzymuje silnik magnetofonu i wyłącza BASIC (gra leży w
;      RAM-ie $9FF0-$BFFF),
;   2. wyświetla ekran tytułowy "RIVER RAID",
;   3. otwiera magnetofon (C:) w trybie ciągłym i wczytuje plik XEX
;      segment po segmencie (obsługa $FFFF, INITAD i RUNAD),
;   4. zamyka kasetę i uruchamia grę przez RUNAD.
;
; Wynik to surowy plik binarny (bez nagłówka XEX) = rekordy boot:
;   mads riverraid_tape.asm -o:riverraid_tape.bin -l -t
; Plik CAS składa potem build_cas.py.
; =====================================================================

        opt h-                  ; surowy plik, bez nagłówka XEX

; --- adresy systemu operacyjnego ---
CIOV    = $E456
stage   = $D8
t0lo    = $D9                   ; diagnostyka czasu (RTCLOK)
t0hi    = $DA
topl    = $DB
toph    = $DC
e_lo    = $DD
e_hi    = $DE                   ; litera etapu (diagnostyka bledu)
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
COLOR1  = $02C5
COLOR2  = $02C6
COLOR4  = $02C8
SAVMSC  = $58
PORTB   = $D301
PACTL   = $D302

; --- polecenia CIO ---
CMD_OPEN  = $03
CMD_GET   = $07
CMD_CLOSE = $0C
IOCB1     = $10                 ; numer kanału * 16 (kanał #1)

; --- położenie napisów na ekranie (wiersz * 40 + kolumna) ---
OFS_TITLE = 9*40+15
OFS_SUB   = 12*40+11
OFS_ERR   = 16*40+13
OFS_ERR2  = 19*40+13

; --- zmienne na stronie zerowej ---
scr     = $CC                   ; wskaźnik do pamięci ekranu (2 B)
src     = $CE                   ; wskaźnik do tekstu (2 B)
segst   = $D0                   ; początek segmentu (2 B)
segend  = $D2                   ; koniec segmentu (2 B)
dst     = $D4                   ; adres docelowy odczytu (2 B)
len     = $D6                   ; długość odczytu (2 B)

        org $0600

; --- nagłówek rekordu boot (6 bajtów) ---
boot    dta 0                           ; flagi
        dta b([ldr_end-boot+127]/128)   ; liczba rekordów boot po 128 B
        dta a(boot)                     ; adres ładowania
        dta a(rts_vec)                  ; CASINI - wywoływany przy RESET

; --- wejście: system skacze tutaj (adres ładowania + 6) ---
start   lda #$3C
        sta PACTL               ; zatrzymaj magnetofon na czas przygotowań
        lda #$FF
        sta PORTB
        lda $14
        sta t0lo
        lda $13
        sta t0hi               ; wyłącz BASIC - RAM widoczny pod $A000-$BFFF

        lda #$92
        sta COLOR2              ; tło
        sta COLOR4              ; ramka
        lda #$0E
        sta COLOR1              ; jasność tekstu

; --- czyszczenie ekranu (24 x 40 = 960 bajtów) ---
        lda SAVMSC
        sta scr
        lda SAVMSC+1
        sta scr+1
        lda #0
        tay
        ldx #3                  ; 3 pełne strony (768 B)
clr1    sta (scr),y
        iny
        bne clr1
        inc scr+1
        dex
        bne clr1
clr2    sta (scr),y             ; pozostałe 192 bajty (Y = 0..191)
        iny
        cpy #192
        bne clr2

; --- napisy ---
        lda #<OFS_TITLE
        ldx #>OFS_TITLE
        jsr setscr
        lda #<txt1
        sta src
        lda #>txt1
        sta src+1
        ldx #txt1_len
        jsr puts

        lda #<OFS_SUB
        ldx #>OFS_SUB
        jsr setscr
        lda #<txt2
        sta src
        lda #>txt2
        sta src+1
        ldx #txt2_len
        jsr puts

; --- otwarcie magnetofonu (C:) do odczytu, tryb ciągły ---
        jsr setinit             ; INITAD = RTS
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
        lda #$80                ; tryb ciągły (krótkie przerwy IRG)
        sta ICAX2,x
        lda #$0C
        sta CH                  ; udawany klawisz RETURN - pomija "wciśnij PLAY"
        jsr CIOV
        lda #$FF
        sta CH                  ; kasuj "wciśnięty klawisz"
        jsr getdiff
        stx topl
        sta toph
        cpy #1
        beq segloop
        jmp error

; --- pętla segmentów pliku XEX ---
segloop lda #'H'-32
        sta stage
        lda #segst
        jsr rdw                 ; początek segmentu (lub znacznik $FFFF)
        cpy #$88                ; EOF w miejscu nagłówka = koniec pliku
        beq finish
        cpy #1
        bne fail
        lda segst
        and segst+1
        cmp #$FF
        beq segloop             ; znacznik $FFFF - czytaj nagłówek jeszcze raz
        lda #'E'-32
        sta stage
        lda #segend
        jsr rdw                 ; koniec segmentu
        cpy #1
        bne fail
        sec                     ; len = koniec - początek + 1
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
        jsr rdblk               ; dane segmentu prosto pod adres docelowy
        cpy #1
        bne fail
        jsr doinit              ; INITAD, jeśli segment go ustawił
        jmp segloop
fail    jmp error

; --- koniec pliku: zamknij kasetę i uruchom grę ---
finish  ldx #IOCB1
        lda #CMD_CLOSE
        sta ICCOM,x
        jsr CIOV
        lda #$3C
        sta PACTL               ; zatrzymaj magnetofon
        jmp (RUNAD)             ; start gry

; --- błąd: pokaż kod statusu CIO i zatrzymaj się ---
error   tya
        pha                     ; zapamiętaj kod błędu
        lda #$3C
        sta PACTL
        lda #<OFS_ERR
        ldx #>OFS_ERR
        jsr setscr
        lda #<txt_err
        sta src
        lda #>txt_err
        sta src+1
        ldx #txt_err_len
        jsr puts                ; po powrocie Y = liczba znaków
        pla
        pha
        lsr
        lsr
        lsr
        lsr
        tax
        lda hexd,x
        sta (scr),y
        iny
        pla
        and #$0F
        tax
        lda hexd,x
        sta (scr),y
        iny
        lda #0
        sta (scr),y
        iny
        lda stage
        sta (scr),y
        jsr getdiff
        stx e_lo
        sta e_hi
        lda #<OFS_ERR2
        ldx #>OFS_ERR2
        jsr setscr
        ldy #0
        lda toph
        jsr phex
        lda topl
        jsr phex
        lda #0
        sta (scr),y
        iny
        lda e_hi
        jsr phex
        lda e_lo
        jsr phex
        jmp *

; --- podprogramy ---

; rdw: czytaj 2 bajty z kasety do zmiennej na stronie zerowej (adres w A)
rdw     sta dst
        lda #0
        sta dst+1
        sta len+1
        lda #2
        sta len
; rdblk: czytaj len bajtów z kasety pod adres dst; zwraca Y = status CIO
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

; doinit: wywołaj INITAD, jeśli segment go zmienił. Kaseta stoi na czas
; inicjalizacji, żeby nie przegapić kolejnego rekordu.
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

; setscr: scr = SAVMSC + (A + 256*X)
setscr  clc
        adc SAVMSC
        sta scr
        txa
        adc SAVMSC+1
        sta scr+1
        rts

; puts: kopiuj X znaków z (src) na ekran pod (scr); wyjście Y = X wejściowe
puts    ldy #0
puts1   lda (src),y
        sta (scr),y
        iny
        dex
        bne puts1
        rts

getdiff sec
        lda $14
        sbc t0lo
        tax
        lda $13
        sbc t0hi
        rts

phex    pha
        lsr
        lsr
        lsr
        lsr
        tax
        lda hexd,x
        sta (scr),y
        iny
        pla
        and #$0F
        tax
        lda hexd,x
        sta (scr),y
        iny
        rts

; --- dane ---
cname   dta c'C:',$9B
txt1    dta d'RIVER RAID'
txt1_len = *-txt1
txt2    dta d'LADOWANIE Z KASETY'
txt2_len = *-txt2
txt_err dta d'BLAD KASETY $'
txt_err_len = *-txt_err
hexd    dta d'0123456789ABCDEF'
rts_vec rts

ldr_end
