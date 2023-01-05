LIBD_LLVM_SRC = $(wildcard src/d/llvm/*.d) import/llvm/c/target.d

LIBD_LLVM = lib/libd-llvm.a

LIBD_LLVM_IMPORTS = -Iimport

LLVM_CONFIG ?= llvm-config
LDFLAGS_LLVM = $(shell $(LLVM_CONFIG) --ldflags) $(shell $(LLVM_CONFIG) --libs) $(shell $(LLVM_CONFIG) --system-libs)

obj/libd-llvm.o: $(LIBD_LLVM_SRC)
	@mkdir -p lib obj
	$(DMD) -c -of"$@" $(LIBD_LLVM_SRC) -makedeps="$@.deps" $(DFLAGS) $(LIBD_LLVM_IMPORTS)

$(LIBD_LLVM): obj/libd-llvm.o
	ar rcs "$@" $^

check-llvm: $(SDC) $(LIBSDRT) $(PHOBOS)
	cd test/llvm; ./runlit.py . -v

check: check-llvm
.PHONY: check-llvm
