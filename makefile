DMD ?= dmd
ARCHFLAG ?= -m64
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest

LLVM_CONFIG ?= llvm-config
LLVM_LIB = -L-L`$(LLVM_CONFIG) --libdir` `$(LLVM_CONFIG) --libs | sed 's/-l/-L-l/g'`
LIBD_LIB = -L-Llibd-llvm/libd/lib -L-ld -L-Llibd-llvm/lib -L-ld-llvm

LDFLAGS = $(LIBD_LIB) $(LLVM_LIB) -L-lstdc++

PLATFORM = $(shell uname -s)
ifeq ($(PLATFORM),Linux)
	LDFLAGS += -L-ldl -L-lffi
endif

IMPORTS = -I$(LIBD_LLVM_ROOT)/src
SOURCE = src/sdc/*.d

SDC = bin/sdc

LIBD_LLVM_ROOT = libd-llvm
ALL_TARGET = $(SDC)

include libd-llvm/makefile.common

# Add LIBD_SRC to hack around http://d.puremagic.com/issues/show_bug.cgi?id=9571
$(SDC): $(SOURCE) $(LIBD_LLVM) $(LIBD_SRC)
	@mkdir -p bin
	$(DMD) -of$(SDC) $(SOURCE) $(LIBD_SRC) $(DFLAGS) $(LDFLAGS) $(IMPORTS) $(LIBD_LLVM_IMPORTS)

clean:
	rm -rf $(SDC) lib/*.a

doc:
	$(DMD) -o- -op -c -Dddoc index.dd $(SOURCE) $(DFLAGS)

run: $(SDC)
	./$(SDC) -Ilibs tests/test0.d -V

debug: $(SDC)
	gdb --args ./$(SDC) -Ilibs tests/test0.d -V --no-colour-print

.PHONY: clean run debug doc
