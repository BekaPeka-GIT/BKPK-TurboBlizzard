; Prosty program dla Atari XL/XE
; Wypisuje napis BEKAPEKA na ekranie w trybie tekstowym

        org $2000

start
        ; wyczyść ekran przez zapis pustych znaków do $0400..$07FF
        ldx #0
clear
        lda #32
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne clear

        ; wypisz napis BEKAPEKA na ekranie
        ldx #0
print
        lda text,x
        beq done
        sta $0400,x
        inx
        bne print

done
        jmp done

text
        .byte "BEKAPEKA",0
