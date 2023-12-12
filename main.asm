.segment "STARTUP"
.segment "INIT"
.segment "ONCE"
.segment "CODE"

	jmp main

.include "x16.inc"
.include "vera.inc"

tileset_file: .literal "TILES.BIN"
end_tileset_file:

tilemap_file: .literal "MAP.BIN"
end_tilemap_file:

palette_file: .literal "PAL.BIN"
end_palette_file:

vram_destination: .res 3

default_irq			= $8000
zp_vsync_trig		= $30

vram_tileset = $00000
vram_tilemap = $02000
vram_bitmap = $06000
vram_next = $0f600
vram_palette = $1fa00

main:

	lda #$02
	sta veractl

	lda #159
	sta veradchstop

	stz veractl

	; set video mode
	lda #%00000001		; l0 enabled
	jsr set_dcvideo

	; set video scale to 2x
	lda #64
	sta veradchscale
	sta veradcvscale

	lda #1
	ldx #8
	ldy #2
	jsr SETLFS
	lda #(end_tileset_file-tileset_file)
	ldx #<tileset_file
	ldy #>tileset_file
	jsr SETNAM
	lda #(^vram_tileset + 2)
	ldx #<vram_tileset
	ldy #>vram_tileset
	jsr LOAD

	lda #1
	ldx #8
	ldy #2
	jsr SETLFS
	lda #(end_tilemap_file-tilemap_file)
	ldx #<tilemap_file
	ldy #>tilemap_file
	jsr SETNAM
	lda #(^vram_tilemap + 2)
	ldx #<vram_tilemap
	ldy #>vram_tilemap
	jsr LOAD

	lda #1
	ldx #8
	ldy #2
	jsr SETLFS
	lda #(end_palette_file-palette_file)
	ldx #<palette_file
	ldy #>palette_file
	jsr SETNAM
	lda #(^vram_palette + 2)
	ldx #<vram_palette
	ldy #>vram_palette
	jsr LOAD

	;lda #(<(vram_tileset >> 9) | (0 << 1) | 0)
	;							;  height    |  width
	;sta veral0tilebase

	;; set the tile map base address
	;lda #<(vram_tilemap >> 9)
	;sta veral0mapbase

	;; set the l0 tile mode	
	;lda #%10100010 	; height (2-bits) - 2 (128 tiles)
	;				; width (2-bits) - 2 (128 tiles
	;				; T256C - 0
	;				; bitmap mode - 0
	;				; color depth (2-bits) - 3 (4bpp)
	;sta veral0config

	; clear the bitmap
	ldx #0
	ldy #150
	vset vram_bitmap

	; initialize each bitmap byte with black/black
	lda #$00

@y_loop:

@x_loop:

	sta veradat
	inx
	bne @x_loop

	dey
	bne @y_loop

	lda #(<(vram_bitmap >> 9) | (0 << 1) | 0)
								;  height    |  width
	sta veral0tilebase

	; set the l0 tile mode	
	lda #%00000110 	; height (2-bits)
					; width (2-bits)
					; T256C - 0
					; bitmap mode - 1
					; color depth (2-bits) - 2 (4bpp)
	sta veral0config
	
	; set video mode
	lda #%00010001		; l0 enabled
	jsr set_dcvideo

	lda #%00000100	; DCSEL = 2
	sta veractl

	lda #(vram_tileset >> 9)
	and #%11111100
	ora #%00000000
	sta verafxtilebase

	lda #(vram_tilemap >> 9)
	and #%11111100
	ora #%00000011
	sta verafxmapbase

	lda #%10000111
	sta verafxctrl
	
	lda #%00000110	; DCSEL = 3
	sta veractl

	lda #0
	sta verafxxinclo
	lda #%0000010
	sta verafxxinchi

	lda #<(-40<<1)
	sta verafxyinclo
	lda #>(-40<<1)
	and #%01111111
	sta verafxyinchi

	jsr init_irq

;==================================================
; mainloop
;==================================================
mainloop:
	wai
	jsr check_vsync
	jmp mainloop  ; loop forever

	rts

;==================================================
; init_irq
; Initializes interrupt vector
;==================================================
init_irq:
	lda IRQVec
	sta default_irq
	lda IRQVec+1
	sta default_irq+1
	lda #<handle_irq
	sta IRQVec
	lda #>handle_irq
	sta IRQVec+1
	rts

;==================================================
; handle_irq
; Handles VERA IRQ
;==================================================
handle_irq:
	; check for VSYNC
	lda veraisr
	and #$01
	beq @end
	sta zp_vsync_trig
	; clear vera irq flag
	sta veraisr

@end:
	jmp (default_irq)

;==================================================
; check_vsync
;==================================================
check_vsync:
	lda zp_vsync_trig
	beq @end

	; VSYNC has occurred, handle

	jsr tick

@end:
	stz zp_vsync_trig
	rts

;==================================================
; tick
;==================================================
tick:
	stz veractl		; DCSEL = 0
	lda #$d
	sta veradcborder

	; set up the affine helper
	
	lda #<vram_bitmap
	sta vram_destination
	lda #>vram_bitmap
	sta vram_destination+1
	lda#^vram_bitmap
	sta vram_destination+2

	ldx #0

@draw_next_row:
	lda #%00000110  ; DCSEL = 3
	sta veractl

	lda #%00000100
	ora vram_destination+2
	sta verahi
	lda vram_destination+1
	sta veramid
	lda vram_destination
	sta veralo

	lda #%00001001	; DCSEL = 4
	sta veractl

	lda #0
	sta verafxxposlo
	lda #0
	sta verafxxposhi

	txa				; lazy and simple: use register x as our y position
	sta verafxyposlo
	lda #%00000000
	sta verafxyposhi

	ldy #64
@draw_next_pixel:
	lda veradat2
	sta veradat
	lda veradat2
	sta veradat
	lda veradat2
	sta veradat
	lda veradat2
	sta veradat
	lda veradat2
	sta veradat

	dey
	bne @draw_next_pixel

	; end of the row, so increment destination address with +320
	clc
	lda vram_destination
	adc #<160
	sta vram_destination
	lda vram_destination+1
	adc #>160
	sta vram_destination+1
	lda vram_destination+2
	adc #0
	sta vram_destination+2

	inx
	cpx #30
	bne @draw_next_row

	stz veractl		; DCSEL = 0
	lda #0
	sta veradcborder
@return:
	rts

;==================================================
; set_dcvideo
;==================================================
set_dcvideo:
	pha

	stz veractl

	lda veradcvideo
	and #%00001111
	sta u0L
	pla
	and #%11110000
	ora u0L
	sta veradcvideo
	
	rts


