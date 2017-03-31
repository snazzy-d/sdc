DMD ?= dmd
GCC ?= gcc
NASM ?= nasm
ARCHFLAG ?= -m64
DFLAGS = $(ARCHFLAG) -w -debug -g -unittest
PLATFORM = $(shell uname -s)

# DFLAGS = $(ARCHFLAG) -w -O -release

LLVM_CONFIG ?= llvm-config
LLVM_LIB = `$(LLVM_CONFIG) --ldflags` `$(LLVM_CONFIG) --libs` `$(LLVM_CONFIG) --system-libs`
SDC_LIB = -Llib -lsdc -ld -ld-llvm -lsdmd

# dmd.conf doesn't set the proper -L flags.  
# Fix it here until dmd installer is updated
ifeq ($(PLATFORM),Darwin)
	LD_PATH ?= /Library/D/dmd/lib
endif

NASMFLAGS ?=
LDFLAGS ?=
ifdef LD_PATH
	override LDFLAGS += $(addprefix -L, $(LD_PATH))
endif

override LDFLAGS += $(SDC_LIB) -lphobos2 $(LLVM_LIB)

ifeq ($(PLATFORM),Linux)
	LD_GOLD = $(shell which ld.gold | xargs basename)
	ifeq ($(LD_GOLD),ld.gold)
		override LDFLAGS += -fuse-ld=gold
	endif
	override LDFLAGS += -lstdc++ -export-dynamic
	override NASMFLAGS += -f elf64
endif
ifeq ($(PLATFORM),Darwin)
	override LDFLAGS += -lc++
	override NASMFLAGS += -f macho64
endif
ifeq ($(PLATFORM),FreeBSD)
	override LDFLAGS += -lc++
	override NASMFLAGS += -f elf64
endif

SDLIB_DEPS = $(SDC) bin/sdc.conf

ALL_TARGET = $(ALL_EXECUTABLES) $(LIBSDRT) $(PHOBOS)

include sdlib/sdmd.mak
include src/sdc.mak
include sdlib/sdrt.mak
include sdlib/phobos.mak

all: $(ALL_TARGET)

clean:
	rm -rf obj lib $(ALL_EXECUTABLES)

print-%: ; @echo $*=$($*)

testrunner: $(SDC) $(LIBSDRT) $(PHOBOS)
	cd ./test/runner; ./runner.d

test: testrunner littest

.PHONY: clean run debug doc test testrunner littest

# Secondary without dependency make all temporaries secondary.
.SECONDARY:
