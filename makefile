DMD=dmd
DFLAGS=-w -debug -gc -c -unittest -Iimport
SOURCE=src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/gen/*.d src/sdc/extract/*.d
OBJ=sdc.o
EXE=sdc

CXX=g++
CXXFLAGS=-m32
PHOBOS2=-lphobos2
LIBLLVM=-lLLVM-2.8
LDFLAGS=`llvm-config --ldflags` $(PHOBOS2) $(LIBLLVM) libllvm-c-ext.a

all:
	$(DMD) -of$(OBJ) $(SOURCE) $(DFLAGS)
	$(CXX) $(CXXFLAGS) -o$(EXE) $(OBJ) $(LDFLAGS)

