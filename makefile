DMD ?= dmd
ARCHFLAG ?= -m64
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest

LLVM_CONFIG ?= llvm-config
LLVM_LIB = -L-L`$(LLVM_CONFIG) --libdir` `$(LLVM_CONFIG) --libs | sed 's/-l/-L-l/g'`
# LLVM_LIB = `$(LLVM_CONFIG) --libs` `$(LLVM_CONFIG) --ldflags`
LIBD_LIB = -L-Llib -L-ld-llvm -L-ld
# LIBD_LIB = -Llib -ld-llvm -ld

LDFLAGS = $(LIBD_LIB) $(LLVM_LIB) -L-lstdc++
# LDFLAGS = $(LIBD_LIB) $(LLVM_LIB) -lstdc++

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
$(SDC): $(SOURCE) $(LIBD) $(LIBD_LLVM)
	@mkdir -p bin
	$(DMD) -of$(SDC) $(SOURCE) $(DFLAGS) $(LDFLAGS) $(IMPORTS) $(LIBD_LLVM_IMPORTS)
	# gdc -o $(SDC) $(SOURCE) $(LIBD_SRC) -m64 $(LDFLAGS) $(IMPORTS) $(LIBD_LLVM_IMPORTS)

clean:
	rm -rf $(SDC) lib/*.a

doc:
	$(DMD) -o- -op -c -Dddoc index.dd $(SOURCE) $(DFLAGS)

run: $(SDC)
	./$(SDC) -Ilibs tests/test0.d -V

debug: $(SDC)
	gdb --args ./$(SDC) -Ilibs tests/test0.d -V --no-colour-print

.PHONY: clean run debug doc
