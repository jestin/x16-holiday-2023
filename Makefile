NAME = HOLIDAY2023
ASSEMBLER6502 = cl65
ASFLAGS = -t cx16 -l $(NAME).list

PROG = $(NAME).PRG
LIST = $(NAME).list
MAIN = main.asm
SOURCES = $(MAIN) \
		  x16.inc \
		  vera.inc

RESOURCES = TILES.BIN \
			PAL.BIN \
			MAP.BIN

all: $(PROG)

resources: $(RESOURCES)

$(PROG): $(SOURCES)
	$(ASSEMBLER6502) $(ASFLAGS) -o $(PROG) $(MAIN)

TILES.BIN: Tiles.xcf
	gimp -i -d -f -b '(export-vera "Tiles.xcf" "TILES.BIN" 0 0 4 8 8 0 1 1)' -b '(gimp-quit 0)'

PAL.BIN: TILES.BIN
	cp TILES.BIN.PAL PAL.BIN

MAP.BIN: holiday_map_2023.tmx
	tmx2vera holiday_map_2023.tmx -l terrain MAP.BIN

run: all resources
	x16emu -prg $(PROG) -run -scale 2 -debug

clean:
	rm -f $(PROG) $(LIST)

clean_resources:
	rm -f $(RESOURCES)

cleanall: clean clean_resources
