; =========================================================
; {{NAZWA}} — {{OPIS}}
; Atari XL/XE, MADS
; =========================================================

; --- rejestry OS (cienie) ---
RTCLOK  = $12           ; zegar ramek (3 bajty, $14 = najmłodszy)
SAVMSC  = $58           ; adres pamięci ekranu (2 bajty)
COLOR1  = $2C5          ; kolor znaków (luminancja) w GR.0
COLOR2  = $2C6          ; tło w GR.0
COLOR4  = $2C8          ; ramka
CH      = $2FC          ; ostatni klawisz ($FF = brak)

; --- strona zerowa (wolne dla użytkownika: $80-$FF bez BASIC-a) ---
ptr     = $80

        org $2000

start
        lda #$00
        sta COLOR2
        sta COLOR4
        lda #$0E
        sta COLOR1

        lda SAVMSC
        sta ptr
        lda SAVMSC+1
        sta ptr+1

        ldy #0
print   lda text,y
        beq loop
        sta (ptr),y
        iny
        bne print

loop    jmp loop

text    dta d'{{NAZWA}}',0      ; d'' = kody INTERNAL (ekranowe)

        run start
