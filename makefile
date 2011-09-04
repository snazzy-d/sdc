include makefile.common

PLATFORM = $(shell uname -s)
ARCHFLAG ?= -m32
SOURCE = $(SOURCE_WILDCARDS)
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest -Iimport
OBJ = sdc.o
EXE = bin/sdc

PHOBOS2 = -lphobos2
LIBLLVM = $(LLVMDIR)/*.a
LDFLAGS = -L-lstdc++ $(LIBLLVM) 

ifeq ($(PLATFORM),Linux)
LDFLAGS += -L-ldl
endif

all: $(EXE)

$(EXE): $(SOURCE)
	@mkdir -p bin
	$(DMD) -of$(EXE) $(SOURCE) $(DFLAGS) $(LDFLAGS)

clean:
	@rm $(EXE)

run: $(EXE)
	./$(EXE) -Ilibs compiler_tests/test0.d -V

debug: $(EXE)
	gdb --args ./$(EXE) -Ilibs compiler_tests/test0.d -V --no-colour-print

.PHONY: clean run debug
