DMD=dmd
DFLAGS=-w -debug -gc -c -unittest -Iimport
SOURCE=src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/gen/*.d
OBJ=sdc.o
EXE=sdc.bin

# Apologies for the specificness of this.
# In time this will change. For now, fill in your details.
# LIBLLVM must be a 32 bit SO.
CXX=g++
CXXFLAGS=-m32
PHOBOS2=/usr/lib/libphobos2.a
DRUNTIME=/usr/lib/libdruntime.a
LIBLLVM=/home/bernard/Projects/sdc/libLLVM-2.7.so
LDFLAGS=`llvm-config --ldflags` $(PHOBOS2) $(DRUNTIME) $(LIBLLVM)

all:
	$(DMD) -of$(OBJ) $(SOURCE) $(DFLAGS)
	$(CXX) $(CXXFLAGS) -o$(EXE) $(OBJ) $(LDFLAGS)

