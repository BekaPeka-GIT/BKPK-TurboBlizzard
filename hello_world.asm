; =========================================================
; HELLO WORLD — przewijany napis w trybie graficznym
; Atari XL/XE, MADS
; ANTIC mode $B (GR.6): 160x96, 1 bit/piksel (1 piksel = 1 color clock).
; Litery kopiowane z fontu w ROM ($E000) do bufora 8 linii x 64 B.
; Scroll: HSCROL (płynnie, 1 piksel/ramkę) + LMS w display liście (co 8 pikseli).
; =========================================================

; --- rejestry OS (cienie) ---
RTCLOK  = $12           ; zegar ramek (3 bajty, $14 = najmłodszy)
SDLSTL  = $230          ; adres display listy (2 bajty)
COLOR0  = $2C4          ; kolor pikseli (COLPF0)
COLOR4  = $2C8          ; tło i ramka (COLBK)
CHROM   = $E000         ; font w ROM

; --- rejestry sprzętowe ---
HSCROL  = $D404         ; przesunięcie poziome (0-15 color clocks), brak cienia

; --- bufor napisu ---
BUF     = $3000         ; 8 linii x 64 B = 512 B, wyrównany do strony
BPL     = 64            ; bajtów na linię bufora
TXTCOL  = 24            ; bajt, od którego leży napis (poza oknem przy pos=0)
WRAP    = TXTCOL+TEXTLEN ; pos, przy którym napis zniknął z lewej strony

; --- strona zerowa ---
src     = $80           ; wskaźnik na znak w ROM
dst     = $82           ; wskaźnik do bufora
line    = $84           ; numer linii znaku 0..7
pos     = $85           ; scroll zgrubny (bajty)
fine    = $86           ; scroll płynny (wartość HSCROL 7..0)

        org $2000

start
        ; wyczyść bufor ($3000-$31FF)
        lda #0
        tax
clear   sta BUF,x
        sta BUF+$100,x
        inx
        bne clear

        ; narysuj napis do bufora
        ldx #0
char    lda text,x      ; src = CHROM + kod*8
        sta src
        lda #0
        asl src
        rol @
        asl src
        rol @
        asl src
        rol @
        ora #>CHROM
        sta src+1

        txa             ; dst = BUF + TXTCOL + x
        clc
        adc #<(BUF+TXTCOL)
        sta dst
        lda #>(BUF+TXTCOL)
        adc #0
        sta dst+1

        lda #0
        sta line
copy    ldy line
        lda (src),y
        ldy #0
        sta (dst),y
        lda dst         ; następna linia bufora
        clc
        adc #BPL
        sta dst
        bcc @+
        inc dst+1
@       inc line
        lda line
        cmp #8
        bne copy

        inx
        cpx #TEXTLEN
        bne char

        ; kolory: jasnożółte piksele na granatowym tle
        lda #$1E
        sta COLOR0
        lda #$82
        sta COLOR4

        ; stan początkowy scrolla
        lda #0
        sta pos
        lda #7
        sta fine
        sta HSCROL
        jsr setlms

        ; przełącz display listę tuż po VBI, żeby OS nie skopiował połowy adresu
        jsr vsync
        lda #<dlist
        sta SDLSTL
        lda #>dlist
        sta SDLSTL+1

        ; pętla główna: 1 piksel w lewo na ramkę
loop    jsr vsync
        dec fine
        bpl setfine
        lda #7          ; minęło 8 pikseli: przesuń LMS o bajt
        sta fine
        inc pos
        lda pos
        cmp #WRAP
        bne @+
        lda #0
        sta pos
@       jsr setlms
setfine lda fine
        sta HSCROL
        jmp loop

; czekaj na początek nowej ramki (OS zwiększa RTCLOK w VBI)
vsync   lda RTCLOK+2
@       cmp RTCLOK+2
        beq @-
        rts

; wpisz BUF + linia*64 + pos do 8 instrukcji LMS
; (młodszy bajt max 192+WRAP < 256, więc starszy bajt się nie zmienia)
setlms  ldx #0
        ldy #0
@       lda lmslo,y
        clc
        adc pos
        sta lms+1,x
        inx
        inx
        inx
        iny
        cpy #8
        bne @-
        rts

lmslo
        .rept 8
        dta <(BUF+#*BPL)
        .endr

text    dta d'Hello World'      ; kody INTERNAL = indeksy w foncie ROM
TEXTLEN = *-text

; --- display lista (nie może przekraczać granicy 1 KB) ---
        org $2800
dlist   :14 dta $70             ; 112 pustych linii (napis na środku ekranu)
lms
        .rept 8
        dta $5B,a(BUF+#*BPL)    ; mode $B + LMS + HSCROL, 2 linie skanowania
        .endr
        dta $41,a(dlist)        ; JVB

        run start
