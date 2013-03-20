DMD ?= dmd
PLATFORM = $(shell uname -s)
ARCHFLAG ?= -m64
SOURCE = src/sdc/*.d
# Hack around http://d.puremagic.com/issues/show_bug.cgi?id=9571
SOURCE += libd-llvm/libd/src/d/*.d libd-llvm/libd/src/d/*/*.d
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest -Isrc -Iimport -Ilibd-llvm/import -Ilibd-llvm/src -Ilibd-llvm/libd/src
EXE = bin/sdc

LLVM_CONFIG ?= llvm-config
LLVM_LIB = -L-L`$(LLVM_CONFIG) --libdir` `$(LLVM_CONFIG) --libs | sed 's/-l/-L-l/g'`
LIBD_LIB = -L-Llibd-llvm/libd/lib -L-ld -L-Llibd-llvm/lib -L-ld-llvm

LDFLAGS = $(LIBD_LIB) $(LLVM_LIB) -L-lstdc++

ifeq ($(PLATFORM),Linux)
	LDFLAGS += -L-ldl -L-lffi
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
