; Prosty program dla Atari, który wypisuje napis BEKAPEKA na ekranie
; Kompilacja: mads -o:bekapeka_display.xex bekapeka_display.asm

        org $2000

start
        ldx #0

loop
        lda text,x
        beq done
        sta $0400,x
        inx
        bne loop

done
        jmp done

text
        .byte "BEKAPEKA",0
