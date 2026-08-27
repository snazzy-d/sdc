DMD ?= dmd
RDMD ?= rdmd
AS ?= as

ARCH ?= $(shell uname -m)
PLATFORM = $(shell uname -s)

ARCHFLAG ?= -m64
DFLAGS = $(ARCHFLAG) -Isrc -w -debug -g
# DFLAGS = $(ARCHFLAG) -w -O -release

ASFLAGS ?=
LDFLAGS ?=

# Useful for CI.
ifdef USE_LOWMEM
	override DFLAGS += -lowmem
endif

ifdef LD_PATH
	override LDFLAGS += $(addprefix -L, $(LD_PATH))
endif

ifeq ($(PLATFORM),Linux)
	LD_LLD = $(shell which ld.lld | xargs basename)
	ifeq ($(LD_LLD),ld.lld)
		override LDFLAGS += -fuse-ld=lld
	endif
	override LDFLAGS += -lstdc++ -export-dynamic
endif
ifeq ($(PLATFORM),Darwin)
	override LDFLAGS += -lc++ -Wl,-export_dynamic
endif
ifeq ($(PLATFORM),FreeBSD)
	override LDFLAGS += -lc++
endif

# To make sure make calls all
default: all

include src/sdc.mak
include src/sdfmt.mak
include test/unit.mak

all: $(ALL_EXECUTABLES) $(ALL_TOOLS) $(LIBSDRT) $(LIBDMDALLOC) $(PHOBOS)

check: all

clean:
	rm -rf obj lib bin/sdconfig $(ALL_EXECUTABLES) $(ALL_TOOLS)

print-%: ; @echo $*=$($*)

.PHONY: check clean default

# Secondary without dependency make all temporaries secondary.
.SECONDARY:

include $(shell test -d obj && find obj/ -type f -name '*.deps')
