
; Prepare stuff to be done during vblank
; This is called from the lcd interrupt, at line $70
; GbcPrepareVBlank::
; 	ld a, 2
; 	ldh [rWBK], a
; 	call RefreshWindowPalettesPreVBlank
; 	call RefreshPalettesPreVBlank
; 	xor a
; 	ldh [rWBK], a
; 	ret

GbcPrepareVBlank::
	; Save whichever WRAM bank was active when the STAT interrupt fired.
	ldh a, [rWBK]
	ld b, a

	; Switch to the color engine's WRAM2.
	ld a, 2
	ldh [rWBK], a

	; The outer return address is currently in the original WRAM bank.
	; From this point until we restore that bank, all nested stack usage
	; deliberately happens in WRAM2.
	push bc

	call RefreshWindowPalettesPreVBlank
	call RefreshPalettesPreVBlank

	; Recover the original WRAM bank while WRAM2 is still selected.
	pop bc
	ld a, b

	; Restore the original bank BEFORE RET, so GbcPrepareVBlank's
	; return address becomes visible again.
	ldh [rWBK], a
	ret

; Refresh palettes based on BGP and OBP registers
; Assumes wram bank 2 is loaded
RefreshPalettesPreVBlank:
	ld a, [W2_ForceBGPUpdate]
	or a
	jr nz, .updatebgp

	ldh a, [rBGP]
	ld b, a
	ld a, [W2_LastBGP]
	cp b
	jr z, .checkSprPalettes

.updatebgp:
	ld a, 1
	ld [W2_BgPaletteDataModified], a

	ld b, $00
	ld hl, W2_BgPaletteDataBuffer

	ldh a, [rBGP]
	and a
	jr nz, .bgpNotWhite
	call SetWhiteColor
	jr .checkSprPalettes
.bgpNotWhite
	cp $ff
	jr nz, .bgpNotBlack
	call SetBlackColor
	jr .checkSprPalettes
.bgpNotBlack

.doNextBgPal:
	ld e, 4

	ldh a, [rBGP]
	ld d, a

.doNextBgColor:
	ld a, d
	call SetColor
	srl d
	srl d

	dec e
	jr nz, .doNextBgColor
	inc b
	bit 3, b ; b >= 8?
	jr z, .doNextBgPal

.checkSprPalettes
	ld a, [W2_ForceOBPUpdate]
	or a
	jr nz, .updateobjp
	ldh a, [rOBP0]
	ld b, a
	ld a, [W2_LastOBP0]
	cp b
	jr nz, .updateobjp
	ldh a, [rOBP1]
	ld b, a
	ld a, [W2_LastOBP1]
	cp b
	jr z, .end

.updateobjp
	ld a, 1
	ld [W2_SprPaletteDataModified], a

	ld b, $08
	ld hl, W2_SprPaletteDataBuffer

	ldh a, [rOBP0]
	and a
	jr nz, .obpNotWhite
	call SetWhiteColor
	jr .end
.obpNotWhite
	cp $ff
	jr nz, .obpNotBlack
	call SetBlackColor
	jr .end
.obpNotBlack

.doNextSprPal
	ld e, 4

	ld a, [W2_UseOBP1]
	and a
	jr z, .obp0
	ld a, 11
	cp b
	jr nc, .obp0
.obp1
	ldh a, [rOBP1]
	ld d, a
	jr .doNextSprColor
.obp0
	ldh a, [rOBP0]
	ld d, a

.doNextSprColor
	ld a, d
	call SetColor
	srl d
	srl d
	dec e
	jr nz, .doNextSprColor

	inc b
	bit 4, b ; b >= 16?
	jr z, .doNextSprPal

.end
	ldh a, [rBGP]
	ld [W2_LastBGP], a
	ldh a, [rOBP0]
	ld [W2_LastOBP0], a
	ldh a, [rOBP1]
	ld [W2_LastOBP1], a
	xor a
	ld [W2_ForceBGPUpdate], a
	ld [W2_ForceOBPUpdate], a
	ret


; Draw window palettes; this is done before vblank so it can be efficiently DMA'd.
RefreshWindowPalettesPreVBlank:
	ldh a, [hAutoBGTransferEnabled]
	and a
	ret z

	ldh a, [rWBK]
	ld b, a
	ld a, $02
	ldh [rWBK], a
	push bc ; Push last wram bank

	; Check that vblank has updated the window from last frame (if not, let it catch up)
	ld hl, W2_UpdatedWindowPortion
	ld a, [hl]
	and a
	jp nz, .palettesDone
	ld [hl], 1

	ldh a, [hAutoBGTransferPortion]
	and a
	jr z, .firstThird
	dec a
	jr z, .secondThird
.thirdThird
	ld de, wTileMap + 6 * 20 * 2
	jr .startCopy
.firstThird:
	ld de, wTileMap
	jr .startCopy
.secondThird:
	ld de, wTileMap + 6 * 20

; de now points to map data in wram
.startCopy:

; BEGIN loading palettes

	ld hl, W2_ScreenPalettesBuffer

	ld b, 6

	ld a, [W2_TileBasedPalettes]
	and a
	jr nz, .tileBasedPalettes

.staticMapPalettes: ; Palettes are loaded from a 20x18 grid of palettes
	; If the window transfer destination changed, we'll need to rewrite everything
	ld a, [W2_LastAutoCopyDest]
	ld b, a
	ldh a, [hAutoBGTransferDest + 1]
	cp b
	jr z, .noDestChange
	ld [W2_LastAutoCopyDest], a
	ld a, 3
	ld [W2_StaticPaletteMapChanged], a
.noDestChange

	ld a, [W2_StaticPaletteMapChanged]
	and a
	jp z, .palettesDone

	ld [W2_StaticPaletteMapChanged_vbl], a ; Only this will signal vblank to refresh the window palettes

	dec a
	ld [W2_StaticPaletteMapChanged], a

	push hl
	ld h, d
	ld l, e
	ld de, W2_TilesetPaletteMap - wTileMap
	add hl, de
	ld d, h
	ld e, l ; de now points to the appropriate location in the palette grid @ W2_TilesetPaletteMap
	pop hl

	ld b, 6
.drawRow_Pal
	ld c, 20
.palLoop
	ld a, [de]
	inc de
	ld [hli], a
	dec c
	jr nz, .palLoop

	ld a, 32 - 20
	add l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	dec b
	jr nz, .drawRow_Pal

	jr .palettesDone

.tileBasedPalettes: ; Palettes are loaded based on the tile at that location
	push hl
	ld h, d
	ld l, e
	pop de
.drawRow
	push bc
	ld b, W2_TilesetPaletteMap >> 8
REPT 20
	ld a, [hli]
	ld c, a
	ld a, [bc]
	ld [de], a
	inc e
ENDR

	ld a, 32 - 20
	add e
	ld e, a
	jr nc, .noCarry2
	inc d
.noCarry2
	pop bc
	dec b
	jr nz, .drawRow

.palettesDone:
	pop af
	ldh [rWBK], a
	ret

GbcVBlankHook::
        push af
        push bc
        push hl

        ; ------------------------------------------------------------
        ; Schedule pre-VBlank palette preparation.
        ;
        ; Pikachu's Beach uses STAT Mode-0/HBlank (bit 3).
        ; During normal gameplay, use the LYC source instead.
        ; ------------------------------------------------------------
        ldh a, [rSTAT]
        bit 3, a
        jr nz, .skipStatSetup

        ldh a, [rIE]
        or IE_STAT
        ldh [rIE], a

        ld a, $6e
        ldh [rLYC], a

        ldh a, [rSTAT]
        or $40                     ; STAT LYC interrupt enable
        ldh [rSTAT], a

.skipStatSetup

        ; ------------------------------------------------------------
        ; Save the current SP while WRAM bank 1 is still visible.
        ; hSPTemp is already used elsewhere for this exact purpose.
        ; ------------------------------------------------------------
        ld hl, sp + 0
        ld a, h
        ldh [hSPTemp], a
        ld a, l
        ldh [hSPTemp + 1], a

        ; Save current WRAM bank in B.
        ldh a, [rWBK]
        ld b, a

        ; Color engine state lives in WRAM bank 2.
        ld a, 2
        ldh [rWBK], a

        ; Give routines called while WRAM2 is selected their own
        ; temporary stack. Atozuke color state only occupies
        ; $D000-$D7FF, so the upper half is available here.
        ld sp, $dfff

        ; ------------------------------------------------------------
        ; The donor avoids refreshing palettes on frames where a
        ; scrolling row/column was drawn.
        ; ------------------------------------------------------------
        ld hl, W2_DrewRowOrColumn
        ld a, [hl]
        and a
        jr nz, .skipPaletteRefresh

        call RefreshPalettesVBlank

.skipPaletteRefresh
        xor a
        ld [W2_DrewRowOrColumn], a

        ; ------------------------------------------------------------
        ; Restore the original stack pointer BEFORE returning to
        ; WRAM bank 1.
        ; ------------------------------------------------------------
        ldh a, [hSPTemp]
        ld h, a
        ldh a, [hSPTemp + 1]
        ld l, a
        ld sp, hl

        ; Restore previous WRAM bank.
        ld a, b
        ldh [rWBK], a

        ; Now the outer interrupt stack is visible again.
        pop hl
        pop bc
        pop af
        ret

; GbcVBlankHook::
; 	push af
; 	push bc
; 	push hl

; 	; Normal GBC gameplay:
; 	; schedule GbcPrepareVBlank through the LYC STAT interrupt.
; 	;
; 	; Pikachu's Beach uses STAT Mode-0/HBlank (bit 3), so don't
; 	; enable our LYC source while that is active.
; 	ldh a, [rSTAT]
; 	bit 3, a
; 	jr nz, .skipStatSetup

; 	ldh a, [rIE]
; 	or IE_STAT
; 	ldh [rIE], a

; 	ld a, $6e
; 	ldh [rLYC], a

; 	ldh a, [rSTAT]
; 	or $40                     ; enable LYC=LY STAT interrupt
; 	ldh [rSTAT], a

; .skipStatSetup

; 	; Save current WRAM bank in B.
; 	; The stack lives in switchable WRAM, so after switching to
; 	; WRAM bank 2 we must not push/pop/call until WRAM1 is restored.
; 	ldh a, [rWBK]
; 	ld b, a

; 	ld a, 2
; 	ldh [rWBK], a

; 	; Known-safe diagnostic:
; 	; upload one complete real CGB BG palette (8 bytes).
; 	ld a, $80
; 	ldh [rBGPI], a

; 	ld hl, W2_BgPaletteData
; 	ld c, 8

; .loop
; 	ld a, [hli]
; 	ldh [rBGPD], a
; 	dec c
; 	jr nz, .loop

; 	; Restore WRAM bank BEFORE touching the stack.
; 	ld a, b
; 	ldh [rWBK], a

; 	pop hl
; 	pop bc
; 	pop af
; 	ret

; GbcVBlankHook::
; 	push af
; 	push bc
; 	push hl

; 	; Save current WRAM bank in B.
; 	; Do not store it on the stack, because the stack itself
; 	; lives in the switchable $D000-$DFFF region.
; 	ldh a, [rWBK]
; 	ld b, a

; 	ld a, 2
; 	ldh [rWBK], a

; 	; Upload only real BG palette 0.
; 	ld a, $80
; 	ldh [rBGPI], a

; 	ld hl, W2_BgPaletteData
; 	ld c, 8

; .loop
; 	ld a, [hli]
; 	ldh [rBGPD], a
; 	dec c
; 	jr nz, .loop

; 	; Restore the original WRAM bank BEFORE touching the stack.
; 	ld a, b
; 	ldh [rWBK], a

; 	pop hl
; 	pop bc
; 	pop af
; 	ret

; ; This is the last vblank-timing-sensitive thing that's called
; GbcVBlankHook::
; 	call UpdateMovingBgTiles ; Removed from caller to make space

; 	; Use the hblank interrupt to get a head-start with vblank stuff
; 	ldh a, [rIE]
; 	or 2
; 	ldh [rIE], a
; 	ld a, $6e
; 	ldh [rLYC], a
; 	ldh a, [rSTAT]
; 	or $40
; 	ldh [rSTAT], a

; 	ld a, 2
; 	ldh [rWBK], a

; 	; Don't try to refresh palette if a row or column was drawn this frame.
; 	; This isn't really necessary, but it prevents a 1-frame artifact that occurs when
; 	; transitioning between screens, where all sprites are white.
; 	ld hl, W2_DrewRowOrColumn
; 	ld a, [hl]
; 	and a
; 	jr nz, .end

; 	call RefreshPalettesVBlank

; .end
; 	xor a
; 	ld [W2_DrewRowOrColumn], a
; 	ldh [rWBK], a
; 	ret

; GbcVBlankHook::
; 	push af

; 	; Diagnostic palette:
; 	; color 0 = white
; 	; color 1 = red
; 	; color 2 = green
; 	; color 3 = blue
; 	;
; 	; This is deliberately ugly so we can clearly tell
; 	; whether native CGB palette RAM is being used.

; 	ld a, $80 ; palette 0, color 0, auto-increment
; 	ldh [rBGPI], a

; 	; White = $7fff
; 	ld a, $ff
; 	ldh [rBGPD], a
; 	ld a, $7f
; 	ldh [rBGPD], a

; 	; Red = $001f
; 	ld a, $1f
; 	ldh [rBGPD], a
; 	xor a
; 	ldh [rBGPD], a

; 	; Green = $03e0
; 	ld a, $e0
; 	ldh [rBGPD], a
; 	ld a, $03
; 	ldh [rBGPD], a

; 	; Blue = $7c00
; 	xor a
; 	ldh [rBGPD], a
; 	ld a, $7c
; 	ldh [rBGPD], a

; 		; Diagnostic: initialize all 8 CGB OBJ palettes.
; 	; Each one gets:
; 	;   color 0 = white
; 	;   color 1 = red
; 	;   color 2 = green
; 	;   color 3 = blue

; 	ld a, $80
; 	ldh [rOBPI], a

; 	REPT 8
; 		; White = $7fff
; 		ld a, $ff
; 		ldh [rOBPD], a
; 		ld a, $7f
; 		ldh [rOBPD], a

; 		; Red = $001f
; 		ld a, $1f
; 		ldh [rOBPD], a
; 		xor a
; 		ldh [rOBPD], a

; 		; Green = $03e0
; 		ld a, $e0
; 		ldh [rOBPD], a
; 		ld a, $03
; 		ldh [rOBPD], a

; 		; Blue = $7c00
; 		xor a
; 		ldh [rOBPD], a
; 		ld a, $7c
; 		ldh [rOBPD], a
; 	ENDR

; 	pop af
; 	ret


; If necessary, copy palettes which were generated in the pre-vblank routines.
; It takes ~1024 cycles (1.1 scanlines) to write 8 palettes.
; So for each operation, it checks that it's not further than line $97. It'll have lines
; $98 and $00 to work with.
RefreshPalettesVBlank:

.checkBgPalettes
	ld a, [W2_BgPaletteDataModified]
	and a
	jr z, .checkSpritePalettes

	; Check there's enough time in vblank
	call .checkScanline
	jr nc, .end

	ld a, $80
	ldh [rBGPI], a
	ld c, rBGPD & $ff
	ld hl, W2_BgPaletteDataBuffer
	call .load8

	xor a
	ld [W2_BgPaletteDataModified], a

.checkSpritePalettes
	ld a, [W2_SprPaletteDataModified]
	and a
	jr z, .end

	; Check there's enough time in vblank
	call .checkScanline
	jr nc, .end

	ld a, $80
	ldh [rOBPI], a
	ld c, rOBPD & $ff
	ld hl, W2_SprPaletteDataBuffer
	call .load8

	xor a
	ld [W2_SprPaletteDataModified], a

.end
	ret

; Loads 8 palettes. Parameters:
; c = data register (ie. rBGPD)
; hl = source
.load8:
rept 64
	ld a, [hli]
	ld [$ff00+c], a
endr
	ret

; Sets carry flag if there's enough time to load another 8 palettes
.checkScanline
	ldh a, [rLY]
	cp $97
	ret nc
	cp $90
	ccf
	ret

; Sets a palette color from palette #b to the index of last 2 bits of a.
; hl points to a buffer to store the palettes at.
; Used in pre-vblank routines.
SetColor:
	push de
	and 3
	add a
	ld d, a
	ld a, b
	add a
	add a
	add a
	add d
	ld d, W2_BgPaletteData >> 8
	ld e, a ; de points to W2_BgPaletteData (or SprPaletteData)

	ld a, [de]
	inc de
	ld [hli], a
	ld a, [de]
	ld [hli], a

	pop de
	ret

SetBlackColor:
	xor a
	ld c, 8 * 8
.loop
	ld [hli], a
	dec c
	jr nz, .loop
	ret

SetWhiteColor:
	ld a, $ff
	ld c, 8 * 8
.loop
	ld [hli], a
	dec c
	jr nz, .loop
	ret
