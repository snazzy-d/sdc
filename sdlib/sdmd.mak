# Common definitions

LIBSMD_SRC = sdlib/d/rt/eh.d sdlib/d/rt/object.d sdlib/d/rt/dwarf.d

LIBSDMD = lib/libsdmd.a

SDFLAGS ?=
NATIVE_DMD_IMPORTS ?= -I/usr/include/dmd/druntime/import -I/usr/include/dmd/phobos
LIBSDMD_IMPORTS = $(NATIVE_DMD_IMPORTS) -Isdlib

$(LIBSDMD): $(LIBSMD_SRC)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/sdmd.o -makedeps="$@.deps" $(LIBSMD_SRC) $(ARCHFLAG) $(LIBSDMD_IMPORTS)
	ar rcs $(LIBSDMD) obj/sdmd.o
