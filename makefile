DMD=dmd
DFLAGS=-w -debug -gc
SOURCE=src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d
EXE=sdc.bin

all:
	$(DMD) -of$(EXE) $(SOURCE) $(DFLAGS)

