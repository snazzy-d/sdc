DMD=dmd
DFLAGS=-w -debug -gc -c -unittest -Iimport
SOURCE=src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/gen/*.d src/sdc/extract/*.d
OBJ=sdc.o
EXE=sdc

CXX=g++
CXXFLAGS=-m32
PHOBOS2=/usr/lib32/libphobos2.a
DRUNTIME=/usr/lib32/libdruntime.a
LIBLLVM=-lLLVM-2.8
LDFLAGS=`llvm-config --ldflags` $(PHOBOS2) $(DRUNTIME) $(LIBLLVM) libllvm-c-ext.a

all:
	$(DMD) -of$(OBJ) $(SOURCE) $(DFLAGS)
	$(CXX) $(CXXFLAGS) -o$(EXE) $(OBJ) $(LDFLAGS)

