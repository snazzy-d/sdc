include makefile.common

PLATFORM = $(shell uname -s)
ARCHFLAG ?= -m64
SOURCE = $(SOURCE_WILDCARDS)
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest -Iimport
OBJ = sdc.o
EXE = bin/sdc

LIBLLVM = `llvm-config --libs | sed 's/-L/-L-L/g' | sed 's/-l/-L-l/g' -`
LLVM_DIR ?= `llvm-config --includedir`
LLVM_OBJ = llvmExt.o llvmTarget.o

LDFLAGS = $(LIBLLVM) -L-lstdc++

ifeq ($(PLATFORM),Linux)
LDFLAGS += -L-ldl -L-lffi
endif

all: $(EXE)

$(EXE): $(SOURCE) $(LLVM_OBJ)
	@mkdir -p bin
	$(DMD) -of$(EXE) $(SOURCE) $(DFLAGS) $(LDFLAGS) $(LLVM_OBJ)

clean:
	@rm $(EXE) $(LLVM_OBJ)

doc:
	$(DMD) -o- -op -c -Dddoc index.dd $(SOURCE) $(DFLAGS)

run: $(EXE)
	./$(EXE) -Ilibs tests/test0.d -V

debug: $(EXE)
	gdb --args ./$(EXE) -Ilibs tests/test0.d -V --no-colour-print

llvmExt.o:
	g++ import/llvm/Ext.cpp -c -I$(LLVM_DIR) -o llvmExt.o -D_GNU_SOURCE -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS

llvmTarget.o:
	g++ import/llvm/Target.cpp -c -I$(LLVM_DIR) -o llvmTarget.o -D_GNU_SOURCE -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS

.PHONY: clean run debug doc
