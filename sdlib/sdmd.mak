LIBSMD_SRC = sdlib/d/rt/eh.d sdlib/d/rt/object.d sdlib/d/rt/dwarf.d

LIBSDMD = lib/libsdmd.a

SDFLAGS ?=

NATIVE_DMD_FLAGS = $(shell echo "" | dmd -v - 2> /dev/null | sed -ne 's/^DFLAGS\s*//p')
NATIVE_DMD_IMPORTS ?= $(filter -I%, $(NATIVE_DMD_FLAGS))
LIBSDMD_IMPORTS = $(NATIVE_DMD_IMPORTS) -Isdlib

obj/sdmd.o: $(LIBSMD_SRC)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/sdmd.o -makedeps="$@.deps" $(LIBSMD_SRC) $(ARCHFLAG) $(LIBSDMD_IMPORTS)

$(LIBSDMD): obj/sdmd.o
	ar rcs $(LIBSDMD) obj/sdmd.o
