; Macros for color hack

; rst $18 = bankswitch
MACRO CALL_INDIRECT
	ld b, BANK(\1)
	ld hl, \1
	rst _Bankswitch ;Atozuke edit from 18
ENDM

; Compatibility with pokered-gbc.
; Yume calls this operation "callfar".
MACRO farcall
	ld hl, \1
	ld b, BANK(\1)
	rst _Bankswitch
ENDM

MACRO tilepal
; vram bank, pals
; without some code rewrites, only vram0 is usable for now
DEF x = \1 << 3
REPT _NARG +- 1
	db (x | PAL_BG_\2)
	SHIFT
ENDR
ENDM
