DMD=dmd
ARCHFLAG=-m32
DFLAGS=$(ARCHFLAG) -w -debug -gc -unittest -Iimport
SOURCE=src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/gen/*.d
OBJ=sdc.o
EXE=bin/sdc

CXX=g++
CXXFLAGS=$(ARCHFLAG)
PHOBOS2=-lphobos2
LIBLLVM=-L-lLLVM-2.8
LDFLAGS=$(LIBLLVM) libllvm-c-ext.a

all:
	@mkdir -p bin
	$(DMD) -v -of$(EXE) $(SOURCE) $(DFLAGS) $(LDFLAGS)

