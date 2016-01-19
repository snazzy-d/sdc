DMD ?= dmd
GCC ?= gcc
NASM ?= nasm
ARCHFLAG ?= -m64
DFLAGS = $(ARCHFLAG) -w -debug -g -unittest
PLATFORM = $(shell uname -s)

# DFLAGS = $(ARCHFLAG) -w -O -release

LLVM_CONFIG ?= llvm-config
LLVM_LIB = `$(LLVM_CONFIG) --ldflags` `$(LLVM_CONFIG) --libs` `$(LLVM_CONFIG) --system-libs`
LLVM_BIN ?= `$(LLVM_CONFIG) --bindir`
SDC_LIB = -Llib -lsdc -ld-llvm -ld

# dmd.conf doesn't set the proper -L flags.  
# Fix it here until dmd installer is updated
ifeq ($(PLATFORM),Darwin)
	LD_PATH ?= /Library/D/dmd/lib
endif

NASMFLAGS ?=
LDFLAGS ?=
ifdef LD_PATH
	LDFLAGS += $(addprefix -L, $(LD_PATH))
endif

LDFLAGS += $(SDC_LIB) -lphobos2 $(LLVM_LIB)

ifeq ($(PLATFORM),Linux)
	LDFLAGS += -lstdc++ -export-dynamic
	NASMFLAGS += -f elf64
endif
ifeq ($(PLATFORM),Darwin)
	LDFLAGS += -lc++
	NASMFLAGS += -f macho64
endif

SDC_ROOT = sdc
LIBD_ROOT = libd
LIBD_LLVM_ROOT = libd-llvm
LIBSDRT_ROOT = libsdrt
TESTER_ROOT = tester
PHOBOS_ROOT = phobos

LIBSDRT_EXTRA_DEPS = $(SDC) bin/sdc.conf
PHOBOS_EXTRA_DEPS = $(SDC)

ALL_TARGET = $(LIBSDRT) $(PHOBOS)

include sdc/makefile.common
include libsdrt/makefile.common
include tester/makefile.common
include phobos/makefile.common

all: $(ALL_TARGET)

clean:
	rm -rf obj lib $(SDC)

doc:
	$(DMD) -o- -op -c -Dddoc index.dd $(SOURCE) $(DFLAGS)

print-%: ; @echo $*=$($*)

testlibd-llvm: $(SDC) $(LIBSDRT) $(PHOBOS)
	cd ./libd-llvm/tests; ./runlit.py . -v --path=$(LLVM_BIN)

testrunner: $(SDC) $(LIBSDRT) $(PHOBOS)
	cd ./tests; ./runner.d

test: testrunner testlibd-llvm

.PHONY: clean run debug doc test testrunner testlibd-llvm
