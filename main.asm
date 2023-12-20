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
	sta u0L
	lda #>row_inc_lookup
	sta u0H

@draw_next_row:
	lda #%00000110	; DCSEL = 3
	sta veractl

	ldy #0

	lda (u0),y
	iny
	sta verafxxinclo
	lda (u0),y
	iny
	sta verafxxinchi

	lda (u0),y
	iny
	sta verafxyinclo
	lda (u0),y
	iny
	and #%01111111
	sta verafxyinchi

	lda #%00001001	; DCSEL = 4
	sta veractl

	stz verafxxposlo
	stz verafxxposhi

	txa				; lazy and simple: use register x as our y position
	clc
	adc source_y
	sta verafxyposlo
	lda source_y+1
	adc #0
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
	lda u0L
	adc #4
	sta u0L
	lda u0H
	adc #0
	sta u0H

	inx
	cpx #120
	jne @draw_next_row

	; scroll the image
	inc source_y
	bne :+
	inc source_y+1
:

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
.byte 0, 2, <(-0<<1), >(-0<<1)
.byte 0, 2, <(-1<<1), >(-1<<1)
.byte 0, 2, <(-2<<1), >(-2<<1)
.byte 0, 2, <(-3<<1), >(-3<<1)
.byte 0, 2, <(-4<<1), >(-4<<1)
.byte 0, 2, <(-5<<1), >(-5<<1)
.byte 0, 2, <(-6<<1), >(-6<<1)
.byte 0, 2, <(-7<<1), >(-7<<1)
.byte 0, 2, <(-8<<1), >(-8<<1)
.byte 0, 2, <(-9<<1), >(-9<<1)
.byte 0, 2, <(-10<<1), >(-10<<1)
.byte 0, 2, <(-11<<1), >(-11<<1)
.byte 0, 2, <(-12<<1), >(-12<<1)
.byte 0, 2, <(-13<<1), >(-13<<1)
.byte 0, 2, <(-14<<1), >(-14<<1)
.byte 0, 2, <(-15<<1), >(-15<<1)
.byte 0, 2, <(-16<<1), >(-16<<1)
.byte 0, 2, <(-17<<1), >(-17<<1)
.byte 0, 2, <(-18<<1), >(-18<<1)
.byte 0, 2, <(-19<<1), >(-19<<1)
.byte 0, 2, <(-20<<1), >(-20<<1)
.byte 0, 2, <(-21<<1), >(-21<<1)
.byte 0, 2, <(-22<<1), >(-22<<1)
.byte 0, 2, <(-23<<1), >(-23<<1)
.byte 0, 2, <(-24<<1), >(-24<<1)
.byte 0, 2, <(-25<<1), >(-25<<1)
.byte 0, 2, <(-26<<1), >(-26<<1)
.byte 0, 2, <(-27<<1), >(-27<<1)
.byte 0, 2, <(-28<<1), >(-28<<1)
.byte 0, 2, <(-29<<1), >(-29<<1)
.byte 0, 2, <(-30<<1), >(-30<<1)
.byte 0, 2, <(-31<<1), >(-31<<1)
.byte 0, 2, <(-32<<1), >(-32<<1)
.byte 0, 2, <(-33<<1), >(-33<<1)
.byte 0, 2, <(-34<<1), >(-34<<1)
.byte 0, 2, <(-35<<1), >(-35<<1)
.byte 0, 2, <(-36<<1), >(-36<<1)
.byte 0, 2, <(-37<<1), >(-37<<1)
.byte 0, 2, <(-38<<1), >(-38<<1)
.byte 0, 2, <(-39<<1), >(-39<<1)
.byte 0, 2, <(-40<<1), >(-40<<1)
.byte 0, 2, <(-41<<1), >(-41<<1)
.byte 0, 2, <(-42<<1), >(-42<<1)
.byte 0, 2, <(-43<<1), >(-43<<1)
.byte 0, 2, <(-44<<1), >(-44<<1)
.byte 0, 2, <(-45<<1), >(-45<<1)
.byte 0, 2, <(-46<<1), >(-46<<1)
.byte 0, 2, <(-47<<1), >(-47<<1)
.byte 0, 2, <(-48<<1), >(-48<<1)
.byte 0, 2, <(-49<<1), >(-49<<1)
.byte 0, 2, <(-50<<1), >(-50<<1)
.byte 0, 2, <(-51<<1), >(-51<<1)
.byte 0, 2, <(-52<<1), >(-52<<1)
.byte 0, 2, <(-53<<1), >(-53<<1)
.byte 0, 2, <(-54<<1), >(-54<<1)
.byte 0, 2, <(-55<<1), >(-55<<1)
.byte 0, 2, <(-56<<1), >(-56<<1)
.byte 0, 2, <(-57<<1), >(-57<<1)
.byte 0, 2, <(-58<<1), >(-58<<1)
.byte 0, 2, <(-59<<1), >(-59<<1)
.byte 0, 2, <(-60<<1), >(-60<<1)
.byte 0, 2, <(-61<<1), >(-61<<1)
.byte 0, 2, <(-62<<1), >(-62<<1)
.byte 0, 2, <(-63<<1), >(-63<<1)
.byte 0, 2, <(-64<<1), >(-64<<1)
.byte 0, 2, <(-65<<1), >(-65<<1)
.byte 0, 2, <(-66<<1), >(-66<<1)
.byte 0, 2, <(-67<<1), >(-67<<1)
.byte 0, 2, <(-68<<1), >(-68<<1)
.byte 0, 2, <(-69<<1), >(-69<<1)
.byte 0, 2, <(-70<<1), >(-70<<1)
.byte 0, 2, <(-71<<1), >(-71<<1)
.byte 0, 2, <(-72<<1), >(-72<<1)
.byte 0, 2, <(-73<<1), >(-73<<1)
.byte 0, 2, <(-74<<1), >(-74<<1)
.byte 0, 2, <(-75<<1), >(-75<<1)
.byte 0, 2, <(-76<<1), >(-76<<1)
.byte 0, 2, <(-77<<1), >(-77<<1)
.byte 0, 2, <(-78<<1), >(-78<<1)
.byte 0, 2, <(-79<<1), >(-79<<1)
.byte 0, 2, <(-80<<1), >(-80<<1)
.byte 0, 2, <(-81<<1), >(-81<<1)
.byte 0, 2, <(-82<<1), >(-82<<1)
.byte 0, 2, <(-83<<1), >(-83<<1)
.byte 0, 2, <(-84<<1), >(-84<<1)
.byte 0, 2, <(-85<<1), >(-85<<1)
.byte 0, 2, <(-86<<1), >(-86<<1)
.byte 0, 2, <(-87<<1), >(-87<<1)
.byte 0, 2, <(-88<<1), >(-88<<1)
.byte 0, 2, <(-89<<1), >(-89<<1)
.byte 0, 2, <(-90<<1), >(-90<<1)
.byte 0, 2, <(-91<<1), >(-91<<1)
.byte 0, 2, <(-92<<1), >(-92<<1)
.byte 0, 2, <(-93<<1), >(-93<<1)
.byte 0, 2, <(-94<<1), >(-94<<1)
.byte 0, 2, <(-95<<1), >(-95<<1)
.byte 0, 2, <(-96<<1), >(-96<<1)
.byte 0, 2, <(-97<<1), >(-97<<1)
.byte 0, 2, <(-98<<1), >(-98<<1)
.byte 0, 2, <(-99<<1), >(-99<<1)
.byte 0, 2, <(-100<<1), >(-100<<1)
.byte 0, 2, <(-101<<1), >(-101<<1)
.byte 0, 2, <(-102<<1), >(-102<<1)
.byte 0, 2, <(-103<<1), >(-103<<1)
.byte 0, 2, <(-104<<1), >(-104<<1)
.byte 0, 2, <(-105<<1), >(-105<<1)
.byte 0, 2, <(-106<<1), >(-106<<1)
.byte 0, 2, <(-107<<1), >(-107<<1)
.byte 0, 2, <(-108<<1), >(-108<<1)
.byte 0, 2, <(-109<<1), >(-109<<1)
.byte 0, 2, <(-110<<1), >(-110<<1)
.byte 0, 2, <(-111<<1), >(-111<<1)
.byte 0, 2, <(-112<<1), >(-112<<1)
.byte 0, 2, <(-113<<1), >(-113<<1)
.byte 0, 2, <(-114<<1), >(-114<<1)
.byte 0, 2, <(-115<<1), >(-115<<1)
.byte 0, 2, <(-116<<1), >(-116<<1)
.byte 0, 2, <(-117<<1), >(-117<<1)
.byte 0, 2, <(-118<<1), >(-118<<1)
.byte 0, 2, <(-119<<1), >(-119<<1)
