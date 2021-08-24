DMD ?= dmd
GCC ?= gcc
NASM ?= nasm
ARCHFLAG ?= -m64
# DFLAGS = $(ARCHFLAG) -w -debug -g -unittest
DFLAGS = $(ARCHFLAG) -w -debug -g
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
	LD_LLD = $(shell which ld.lld | xargs basename)
	ifeq ($(LD_LLD),ld.lld)
		override LDFLAGS += -fuse-ld=lld
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

# To make sure make calls all
default: all

include sdlib/sdmd.mak
include src/sdc.mak
include sdlib/sdrt.mak
include sdlib/phobos.mak

all: $(ALL_EXECUTABLES) $(LIBSDRT) $(PHOBOS)

clean:
	rm -rf obj lib $(ALL_EXECUTABLES)

print-%: ; @echo $*=$($*)

check-sdc: $(SDC) $(LIBSDRT) $(PHOBOS)
	test/runner/runner.d

check-sdfmt: $(SDFMT)
	test/runner/checkformat.d

check: all check-sdc check-llvm check-sdfmt

.PHONY: check check-sdc check-llvm check-sdfmt clean default

# Secondary without dependency make all temporaries secondary.
.SECONDARY:

include $(shell test -d obj && find obj/ -type f -name '*.deps')
