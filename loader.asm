; Przykładowy odpowiednik loadera XEX dla Atari
; Wypisuje tekst BEKAPEKA na ekran, korzystając ze wskaźnika ekranu z $58/$59

        org $203B

start
        ; ustaw wskaźnik ekranu na aktualną stronę ekranu
        lda $58
        sta $e0
        lda $59
        sta $e1

        ; przesuń wskaźnik o 17 znaków w lewo (jak w loaderze)
        clc
        lda $e0
        adc #$ef
        sta $e0
        lda $e1
        adc #1
        sta $e1

        ; wpisz spację na początek
        lda #$20
        ldy #0
        sta ($e0),y

        ; wypisz tekst do pamięci ekranu
        ldy #1
print_loop
        lda text,y
        cmp #$ff
        beq done
        sta ($e0),y
        iny
        bne print_loop

done
        ; nie wracaj do ROM; pętla, żeby nie wejść w self-test
        jmp done

text
        .byte $42,$45,$4B,$41,$50,$45,$4B,$41,$ff
