# Common definitions

LIBD_LLVM_SRC = $(wildcard src/d/llvm/*.d) import/llvm/c/target.d

LIBD_LLVM = lib/libd-llvm.a

include src/libd.mak

LIBD_LLVM_IMPORTS = -Isrc -Iimport

$(LIBD_LLVM): $(LIBD_LLVM_SRC) $(LIBD_DEP_IR) $(LIBD_DEP_UTIL)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/libd-llvm.o $(LIBD_LLVM_SRC) $(DFLAGS) $(LIBD_LLVM_IMPORTS)
	ar rcs $(LIBD_LLVM) obj/libd-llvm.o

littest: $(SDC) $(LIBSDRT) $(PHOBOS)
	cd test/llvm; ./runlit.py . -v
