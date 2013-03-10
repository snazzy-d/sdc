DMD ?= dmd
PLATFORM = $(shell uname -s)
ARCHFLAG ?= -m64
SOURCE = src/d/llvm/*.d
DFLAGS = $(ARCHFLAG) -w -debug -gc -unittest -Isrc -Iimport
LIBD_LLVM = lib/libd-llvm.a

LLVM_SRC = import/llvm/c/target.d

all: $(LIBD_LLVM)

$(LIBD_LLVM): $(SOURCE) $(LLVM_SRC)
	@mkdir -p lib
	$(DMD) -lib -of$(LIBD_LLVM) $(SOURCE) $(LLVM_SRC) $(DFLAGS)

clean:
	@rm $(LIBD_LLVM)

.PHONY: clean
