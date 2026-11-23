; Faithful re-creation of the machine-code body from loader.xex
; The original binary is emitted byte-for-byte here.

        org $203B

        .byte $A9,$01,$8D,$F0,$02
        .byte $A5,$58,$85,$E0
        .byte $A5,$59,$85,$E1
        .byte $18,$A5,$E0,$69,$EF,$85,$E0
        .byte $A5,$E1,$69,$01,$85,$E1
        .byte $A9,$20,$A0,$00,$91,$E0
        .byte $A0,$00,$B9,$32,$20,$C9,$FF,$F0,$06
        .byte $91,$E0,$C8,$4C,$22,$20
        .byte $4C,$2F,$20
        .byte $2C,$21,$24,$2F,$37,$21,$2E,$29,$25,$FF
        .byte $E0,$02,$E1,$02,$00,$20
