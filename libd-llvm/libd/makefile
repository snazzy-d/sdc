include makefile.common

PLATFORM = $(shell uname -s)
ARCHFLAG ?= -m64
SOURCE = $(SOURCE_WILDCARDS)
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest -Isrc -Iimport
LIBD = lib/libd.a

all: $(LIBD)

$(LIBD): $(SOURCE)
	@mkdir -p lib
	$(DMD) -lib -of$(LIBD) $(SOURCE) $(DFLAGS)

clean:
	@rm $(LIBD)

.PHONY: clean
