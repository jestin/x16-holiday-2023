.macpack longbranch
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

vram_destination:	.res 3
buf_num:			.res 1
source_y:			.res 2

default_irq			= $8000
zp_vsync_trig		= $30

vram_tileset = $00000
vram_tilemap = $02000
horizon_index = $4b00
vram_buffer0 = $06000
vram_buffer0_horizon = vram_buffer0 + horizon_index
vram_buffer1 = $10000
vram_buffer1_horizon = vram_buffer1 + horizon_index
vram_next = $18c00
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

	vset vram_buffer0
	jsr clear_buffer
	vset vram_buffer1
	jsr clear_buffer

	; set the l0 tile mode	
	lda #%00000110 	; height (2-bits)
					; width (2-bits)
					; T256C - 0
					; bitmap mode - 1
					; color depth (2-bits) - 2 (4bpp)
	sta veral0config

	stz buf_num
	
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

	lda #%11100111
	sta verafxctrl
	
	; scroll variable initilization
	stz source_y
	stz source_y+1

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
; clear_buffer
;==================================================
clear_buffer:
	lda #00	; clear colors

	ldx #0
	ldy #150

@y_loop:

@x_loop:

	; writing twice doubles effectively initializes both buffers
	sta veradat

	inx
	bne @x_loop

	dey
	bne @y_loop
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

	lda buf_num
	bne @buffer1

@buffer0:
	; display buffer1
	lda #(<(vram_buffer1 >> 9) | (0 << 1) | 0)
	sta veral0tilebase

	; draw to buffer0
	lda #<vram_buffer0_horizon
	sta vram_destination
	lda #>vram_buffer0_horizon
	sta vram_destination+1
	lda#^vram_buffer0_horizon
	sta vram_destination+2

	inc buf_num
	bra @destination_setup

@buffer1:
	; display buffer0
	lda #(<(vram_buffer0 >> 9) | (0 << 1) | 0)
	sta veral0tilebase

	; draw to buffer1
	lda #<vram_buffer1_horizon
	sta vram_destination
	lda #>vram_buffer1_horizon
	sta vram_destination+1
	lda#^vram_buffer1_horizon
	sta vram_destination+2

	stz buf_num

@destination_setup:
	lda #%00110000
	ora vram_destination+2
	sta verahi
	lda vram_destination+1
	sta veramid
	lda vram_destination
	sta veralo

	; set up the affine helper
	
	ldx #0
	lda #<row_inc_lookup
	sta u1L
	lda #>row_inc_lookup
	sta u1H

@draw_next_row:
	lda #%00000110	; DCSEL = 3
	sta veractl

	ldy #0

	lda (u1),y
	iny
	sta verafxxinclo
	lda (u1),y
	iny
	sta verafxxinchi

	lda (u1),y
	iny
	sta verafxyinclo
	lda (u1),y
	iny
	sta verafxyinchi

	lda #%00001001	; DCSEL = 4
	sta veractl

	lda (u1),y
	iny
	sta verafxxposlo
	lda (u1),y
	iny
	sta verafxxposhi

	lda (u1),y
	iny
	clc
	adc source_y
	sta verafxyposlo
	lda (u1),y
	iny					; don't need yet, and may never.  Remove later
	adc source_y+1
	and #%00000011
	sta verafxyposhi

	ldy #10
@draw_next_pixel:
.repeat 4
.repeat 8
	lda veradat2
.endrepeat
	stz veradat
.endrepeat
	dey
	bne @draw_next_pixel

	; set the row's scale
	lda #%00000111	; DCSEL = 3
	sta veractl

	; increment row lookup
	clc
	lda u1L
	adc #8
	sta u1L
	lda u1H
	adc #0
	sta u1H

	inx
	cpx #120
	jne @draw_next_row

	; scroll the image
	lda source_y
	bne :+
	dec source_y+1
:
	dec source_y

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

row_inc_lookup:
.include "table.inc"
; XINCL (fraction), XINCH, YINCL (fraction), YINCH, XPOSL, XPOSH, YPOSL, YPOSL
; .byte 0, <(1<<1), <(0<<1), <(0<<1), <(0), >(0), 0, 0
