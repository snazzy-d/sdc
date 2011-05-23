DMD=dmd
ARCHFLAG=-m32
LLVMDIR=llvm
DFLAGS=$(ARCHFLAG) -w -debug -gc -unittest -Iimport
SOURCE=src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/gen/*.d src/sdc/java/*.d
OBJ=sdc.o
EXE=bin/sdc

PHOBOS2=-lphobos2
LIBLLVM=$(LLVMDIR)/*.a
LDFLAGS=-L-lstdc++ -L-ldl $(LIBLLVM)

all:
	@mkdir -p bin
	$(DMD) -of$(EXE) $(SOURCE) $(DFLAGS) $(LDFLAGS)

