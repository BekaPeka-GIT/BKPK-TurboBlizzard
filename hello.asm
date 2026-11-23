; Hello World - Atari 65XE
; Assembler: MADS
; Kompilacja: mads hello.asm -o:hello.xex

CIOV    = $E456             ; wektor CIO
ICCOM   = $0342             ; komenda
ICBAL   = $0344             ; adres bufora (lo)
ICBAH   = $0345             ; adres bufora (hi)
ICBLL   = $0348             ; dlugosc bufora (lo)
ICBLH   = $0349             ; dlugosc bufora (hi)
PUTREC  = $09               ; komenda: put record

        org $2000

start   ldx #$00            ; IOCB #0 (E:)
        lda #PUTREC
        sta ICCOM,x
        lda #<msg
        sta ICBAL,x
        lda #>msg
        sta ICBAH,x
        lda #<msglen
        sta ICBLL,x
        lda #>msglen
        sta ICBLH,x
        jsr CIOV            ; wypisz napis

        jmp *               ; petla nieskonczona (napis zostaje na ekranie)

msg     dta c'Hello World',$9b   ; ATASCII + EOL ($9B)
msglen  = *-msg

        run start           ; adres uruchomienia (RUNAD)
