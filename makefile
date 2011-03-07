DMD=dmd
DFLAGS=-m64 -w -debug -gc -unittest -Iimport
SOURCE=src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/gen/*.d src/sdc/extract/*.d
OBJ=sdc.o
EXE=bin/SDC

CXX=g++
CXXFLAGS=-m32
PHOBOS2=-lphobos2
LIBLLVM=-L-lLLVM-2.8
LDFLAGS=$(LIBLLVM) libllvm-c-ext.a

all:
	@mkdir -p bin
	$(DMD) -of$(EXE) $(SOURCE) $(DFLAGS) $(LDFLAGS)

