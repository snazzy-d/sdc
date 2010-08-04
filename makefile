DMD=dmd
DFLAGS=-w -debug -gc -c -unittest -Iimport
SOURCE=src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/gen/*.d src/sdc/extract/*.d
OBJ=sdc.o
EXE=sdc.bin

# Apologies for the specificness of this.
# In time this will change. For now, fill in your details.
# LIBLLVM must be a 32 bit SO.
CXX=g++
CXXFLAGS=-m32
PHOBOS2=/usr/lib32/libphobos2.a
DRUNTIME=/usr/lib32/libdruntime.a
LIBLLVM=/home/bernard/Projects/SDC/libLLVM-2.7.so
LDFLAGS=`llvm-config --ldflags` $(PHOBOS2) $(DRUNTIME) $(LIBLLVM) Ext.o

all: Ext.o
	$(DMD) -of$(OBJ) $(SOURCE) $(DFLAGS)
	$(CXX) $(CXXFLAGS) -o$(EXE) $(OBJ) $(LDFLAGS)

Ext.o: import/llvm/Ext.cpp
	$(CXX) -m32 -c -oExt.o import/llvm/Ext.cpp `llvm-config --cxxflags`

