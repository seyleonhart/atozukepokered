; marcelnote - Pikachu's Beach minigame
LCDC::
	push af

IF DEF(_ATOZUKE_GBC)
	; Native GBC color preparation uses the LYC STAT source
	; (STAT bit 6). Pikachu's Beach instead uses Mode-0/HBlank
	; interrupts (STAT bit 3), so keep that path separate.
	ldh a, [rSTAT]
	bit 6, a
	jr nz, .gbcPrepareVBlank
ENDC

	ldh a, [hLCDCPointer] ; doubles as enabling byte
	and a
	jr z, .noLCDCInterrupt
	push hl
	; [HIGH(wLYOverrides):rLY] --> [$FF00 + [hLCDCPointer]]
	ldh a, [rLY]
	ld l, a
	ld h, HIGH(wLYOverrides)
	ld h, [hl]
	ldh a, [hLCDCPointer]
	ld l, a
	ld a, h
	ld h, $ff
	ld [hl], a
	pop hl
.noLCDCInterrupt
	pop af
	reti

IF DEF(_ATOZUKE_GBC)
.gbcPrepareVBlank
	; GbcPrepareVBlank uses BC, DE and HL heavily.
	push bc
	push de
	push hl

	ld hl, GbcPrepareVBlank
	ld b, BANK(GbcPrepareVBlank)
	rst _Bankswitch

	pop hl
	pop de
	pop bc
	pop af
	reti
ENDC
