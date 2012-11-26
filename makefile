include makefile.common

PLATFORM = $(shell uname -s)
ARCHFLAG ?= -m64
SOURCE = $(SOURCE_WILDCARDS)
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest -Isrc -Iimport
OBJ = sdc.o
EXE = bin/sdc

LIBLLVM = -L-L`llvm-config-3.1 --libdir` `llvm-config-3.1 --libs | sed 's/-l/-L-l/g'`
LLVM_DIR ?= `llvm-config-3.1 --includedir`
LLVM_SRC = import/llvm/c/target.d

LDFLAGS = $(LIBLLVM) -L-lstdc++

ifeq ($(PLATFORM),Linux)
	LDFLAGS += -L-ldl -L-lffi
endif

all: $(EXE)

$(EXE): $(SOURCE) $(LLVM_SRC) $(LLVM_OBJ)
	@mkdir -p bin
	$(DMD) -of$(EXE) $(SOURCE) $(LLVM_SRC) $(DFLAGS) $(LDFLAGS)

clean:
	@rm $(EXE)

doc:
	$(DMD) -o- -op -c -Dddoc index.dd $(SOURCE) $(DFLAGS)

run: $(EXE)
	./$(EXE) -Ilibs tests/test0.d -V

debug: $(EXE)
	gdb --args ./$(EXE) -Ilibs tests/test0.d -V --no-colour-print

.PHONY: clean run debug doc
