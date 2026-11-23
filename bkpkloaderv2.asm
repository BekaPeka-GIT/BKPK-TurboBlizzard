; =========================================================
; SEKCJA 1: LOADER (REKLAMA GRAFICZNA BEKAPEKA)
; =========================================================
    org $0600

ptr = $CC

start
    ; Ustawienie kolorów
    lda #$0F
    sta $02C6       ; COLOR2 (ramka/tło)
    lda #$00
    sta $02C4       ; COLOR0 (kolor elementów)

    ; Kopiowanie adresu pamięci ekranu (SAVMSC)
    lda $58
    sta ptr
    lda $59
    sta ptr+1

    ; Wpisanie pierwszej linii obrazka (18 bajtów)
    ldy #17
print_line1
    lda image_data_l1,y
    sta (ptr),y
    dey
    bpl print_line1

    ; Przejście do drugiej linii ekranu (dodajemy 40 bajtów szerokości ekranu)
    clc
    lda ptr
    adc #40
    sta ptr
    bcc no_carry
    inc ptr+1
no_carry

    ; Wpisanie drugiej linii obrazka (18 bajtów)
    ldy #17
print_line2
    lda image_data_l2,y
    sta (ptr),y
    dey
    bpl print_line2

    ; Czekaj 1 sekundę zamiast na klawisz
    lda #$00
    sta $12
    sta $13
    sta $14
wait_3sec
    lda $14
    cmp #60         ; 1 sekunda przy 60 Hz
    bne wait_3sec

    rts

; =========================================================
; DANE GRAFIKI (Kody wewnętrzne znaków lub matryca bitowa)
; Możesz też użyć: ins 'logo.raw'
; =========================================================
image_data_l1
    dta d'  BEKAPEKA  LOGO  '   ; Linię możesz zdefiniować znakiem d'...' lub surowymi bajtami dta $00, $01...
image_data_l2
    dta d'=================='

; =========================================================
; SEKCJA 1A: PRAWDZYWY LOADER KASETOWY Z LICZNIKIEM SEGMENTÓW
; =========================================================
    org $0700

ldr_loc equ $0700
seg_cnt equ $B0
BPTR    equ $3D
CASRDB  equ $FD7A
CASCLS  equ $FDCF
SCRPTR  equ $CC
SEGMSG  dta c'SEG 00'

rts     dta $60,$01,a(ldr_loc),c"SI"

st      ldx #$ff
        stx $d301
        sta $bfd5

        ldx #0
        stx seg_cnt
        jsr show_seg_counter

        inx
        stx BPTR

cpl     jsr CASRDB
        sta ldr_loc+$80,x
        ldx BPTR
        bpl cpl

nxt_lp  ldx <rts
        ldy >rts
        stx $2e2
        sty $2e3

ldr_lp  jsr CASRDB
        cpy #$88
        bne not_eof
        jmp eof
not_eof

        sta seg_ptr+1
once_l  sta $2e0

        jsr CASRDB
        sta seg_ptr+2
once_h  sta $2e1

        and seg_ptr+1
        cmp #$ff
        beq ldr_lp

        jsr CASRDB
        clc
        adc #1
        sta sge_l+1
        php

        jsr CASRDB

        plp
        adc #0
        sta sge_h+1

        lda #$2c
        sta once_l
        sta once_h

seg_lp  jsr CASRDB
        bpl no_err
        jmp err
no_err

seg_ptr sta $c0de

        inc seg_ptr+1
        bne no_carry_seg
        inc seg_ptr+2
no_carry_seg

        lda seg_ptr+1
sge_l   cmp #0
        lda seg_ptr+2
sge_h   sbc #0
        bcc seg_lp

        inc seg_cnt
        jsr show_seg_counter
        jsr init

        jmp nxt_lp

show_seg_counter
        lda seg_cnt
        ldx #0
seg_tens
        cmp #10
        bcc seg_tens_done
        sec
        sbc #10
        inx
        jmp seg_tens
seg_tens_done
        pha
        txa
        clc
        adc #'0'
        sta SEGMSG+4
        pla
        clc
        adc #'0'
        sta SEGMSG+5

        lda $58
        sta SCRPTR
        lda $59
        sta SCRPTR+1
        clc
        lda SCRPTR
        adc #80
        sta SCRPTR
        bcc seg_no_carry
        inc SCRPTR+1
seg_no_carry
        ldy #0
seg_copy
        lda SEGMSG,y
        sta (SCRPTR),y
        iny
        cpy #6
        bne seg_copy
        rts

init    jsr CASCLS
        jmp ($2e2)

eof     jsr CASCLS
        jmp ($2e0)

err     lda #0
        jsr $EF9C
        jsr $C63E
        bne *

        org ldr_loc+$ff
        brk

; Wykonanie natychmiast po wczytaniu sekcji loadera
    org $02E2
    dta a(start)

; =========================================================
; SEKCJA 2: KOD GRY ($9FF0-$BFFF)
; =========================================================
    org $9FF0
    ins 'RiverRaid.xex', 6, 8208

; =========================================================
; SEKCJA 3: WEKTOR STARTOWY GRY (RUNAD)
; =========================================================
    org $02E0
    dta a($9FF6)