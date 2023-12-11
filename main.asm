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

default_irq			= $8000
zp_vsync_trig		= $30

vram_tileset = $00000
vram_tilemap = $10000
vram_palette = $1fa00

main:

	; set video mode
	lda #%00010001		; l0 enabled
	sta veradcvideo

	; set video scale to 2x
	lda #128
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

	lda #(<(vram_tileset >> 9) | (0 << 1) | 0)
								;  height    |  width
	sta veral0tilebase

	; set the tile map base address
	lda #<(vram_tilemap >> 9)
	sta veral0mapbase

	; set the l0 tile mode	
	lda #%10100010 	; height (2-bits) - 2 (128 tiles)
					; width (2-bits) - 2 (128 tiles
					; T256C - 0
					; bitmap mode - 0
					; color depth (2-bits) - 3 (4bpp)
	sta veral0config

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

	inc veral0vscrolllo
	bne @return
	inc veral0vscrollhi

@return:
	rts



