DMD ?= dmd
GCC ?= gcc
ARCHFLAG ?= -m64
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest

PHOBOS_L ?=

LLVM_CONFIG ?= llvm-config
LLVM_LIB = `$(LLVM_CONFIG) --ldflags` `$(LLVM_CONFIG) --libs`
LIBD_LIB = -Llib -ld-llvm -ld

#NOTE:llvm-3.3 requires adding -stdlib=libstdc++ : see http://mathematica.stackexchange.com/questions/34692/mathlink-linking-error-after-os-x-10-9-mavericks-upgrade
LDFLAGS = -L$(PHOBOS_L) -lphobos2 $(LIBD_LIB) $(LLVM_LIB) -lstdc++ -export-dynamic

PLATFORM = $(shell uname -s)
ifeq ($(PLATFORM),Linux)
	LDFLAGS += -ldl -lffi -lpthread -lm -lncurses
endif
#ifeq ($(PLATFORM),Darwin)
#	LDFLAGS += -c++
#endif

IMPORTS = $(LIBD_LLVM_IMPORTS) -I$(LIBD_LLVM_ROOT)/src
SOURCE = src/sdc/*.d src/util/*.d

SDC = bin/sdc

LIBD_LLVM_ROOT = libd-llvm
LIBSDRT_ROOT = libsdrt
LIBSDRT_EXTRA_DEPS = $(SDC)

ALL_TARGET = $(LIBSDRT)

include libd-llvm/makefile.common
include libsdrt/makefile.common

$(SDC): obj/sdc.o $(LIBD) $(LIBD_LLVM)
	@mkdir -p bin
	gcc -o $(SDC) obj/sdc.o -m64 $(LDFLAGS)

obj/sdc.o: $(SOURCE)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/sdc.o $(SOURCE) $(DFLAGS) $(IMPORTS)

clean:
	rm -rf obj lib $(SDC)

doc:
	$(DMD) -o- -op -c -Dddoc index.dd $(SOURCE) $(DFLAGS)

.PHONY: clean run debug doc
