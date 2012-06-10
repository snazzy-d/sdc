include makefile.common

PLATFORM = $(shell uname -s)
ARCHFLAG ?= -m64
SOURCE = $(SOURCE_WILDCARDS)
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest -Iimport
OBJ = sdc.o
EXE = bin/sdc

ifeq ($(PLATFORM),Linux)
LDFLAGS += -L-ldl
endif

all: $(EXE)

$(EXE): $(SOURCE)
	@mkdir -p bin
	$(DMD) -of$(EXE) $(SOURCE) $(DFLAGS) $(LDFLAGS)

clean:
	@rm $(EXE)

doc:
	$(DMD) -o- -op -c -Dddoc index.dd $(SOURCE) $(DFLAGS)

run: $(EXE)
	./$(EXE) -Ilibs tests/test0.d -V

debug: $(EXE)
	gdb --args ./$(EXE) -Ilibs tests/test0.d -V --no-colour-print

.PHONY: clean run debug doc
