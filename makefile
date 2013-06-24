DMD ?= dmd
GCC ?= gcc
ARCHFLAG ?= -m64
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest

LLVM_CONFIG ?= llvm-config
LLVM_LIB = `$(LLVM_CONFIG) --libs` `$(LLVM_CONFIG) --ldflags`
LIBD_LIB = -Llib -ld-llvm -ld

LDFLAGS = -lphobos2 $(LIBD_LIB) $(LLVM_LIB) -lstdc++ -export-dynamic

PLATFORM = $(shell uname -s)
ifeq ($(PLATFORM),Linux)
	LDFLAGS += -ldl -lffi
endif

IMPORTS = $(LIBD_LLVM_IMPORTS) -I$(LIBD_LLVM_ROOT)/src
SOURCE = src/sdc/*.d

SDC = bin/sdc

LIBD_LLVM_ROOT = libd-llvm
ALL_TARGET = $(SDC)

include libd-llvm/makefile.common

$(SDC): obj/sdc.o $(LIBD) $(LIBD_LLVM)
	@mkdir -p bin
	gcc -o $(SDC) obj/sdc.o -m64 $(LDFLAGS)

obj/sdc.o: $(SOURCE)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/sdc.o $(SOURCE) $(DFLAGS) $(IMPORTS)

clean:
	rm -rf obj lib bin

doc:
	$(DMD) -o- -op -c -Dddoc index.dd $(SOURCE) $(DFLAGS)

run: $(SDC)
	./$(SDC) -Ilibs tests/test0.d -V

debug: $(SDC)
	gdb --args ./$(SDC) -Ilibs tests/test0.d -V --no-colour-print

.PHONY: clean run debug doc
