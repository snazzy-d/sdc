DMD=dmd
ARCHFLAG=-m32
DFLAGS=$(ARCHFLAG) -w -debug -gc -unittest -Iimport
SOURCE=src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/gen/*.d
OBJ=sdc.o
EXE=bin/sdc

PHOBOS2=-lphobos2
LIBLLVM=llvm/*.a
LDFLAGS=-L-lstdc++ -L-ldl $(LIBLLVM)

all:
	@mkdir -p bin
	$(DMD) -of$(EXE) $(SOURCE) $(DFLAGS) $(LDFLAGS)

