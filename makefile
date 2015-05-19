DMD ?= dmd
GCC ?= gcc
ARCHFLAG ?= -m64
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest
PLATFORM = $(shell uname -s)

# DFLAGS = $(ARCHFLAG) -w -O -release

LLVM_CONFIG ?= llvm-config
LLVM_LIB = `$(LLVM_CONFIG) --ldflags` `$(LLVM_CONFIG) --libs`
LIBD_LIB = -Llib -ld-llvm -ld

# dmd.conf doesn't set the proper -L flags.  
# Fix it here until dmd installer is updated
ifeq ($(PLATFORM),Darwin)
	LD_PATH ?= /usr/share/dmd/lib
endif

LDFLAGS ?=
ifdef LD_PATH
	LDFLAGS += $(addprefix -L, $(LD_PATH))
endif

LDFLAGS += -lphobos2 $(LIBD_LIB) $(LLVM_LIB)

ifeq ($(PLATFORM),Linux)
	LDFLAGS += -lstdc++ -export-dynamic -ldl -lffi -lpthread -lm -lncurses
endif
ifeq ($(PLATFORM),Darwin)
	LDFLAGS += -lc++ -lncurses
endif

SDC_ROOT = sdc
LIBD_ROOT = libd
LIBD_LLVM_ROOT = libd-llvm
LIBSDRT_ROOT = libsdrt

LIBSDRT_EXTRA_DEPS = $(SDC) bin/sdc.conf

ALL_TARGET = $(LIBSDRT)

include sdc/makefile.common
include libsdrt/makefile.common

clean:
	rm -rf obj lib $(SDC)

doc:
	$(DMD) -o- -op -c -Dddoc index.dd $(SOURCE) $(DFLAGS)

print-%: ; @echo $*=$($*)

test: $(SDC) $(LIBSDRT)
	cd ./tests; ./runner.d

.PHONY: clean run debug doc test
