# Common definitions

LIBSMD_SRC = sdlib/d/rt/eh.d sdlib/d/rt/object.d sdlib/d/rt/dwarf.d

LIBSDMD = lib/libsdmd.a

SDFLAGS ?=
LIBSDMD_IMPORTS = -I/usr/include/dmd/druntime/import -I/usr/include/dmd/phobos -Isdlib

$(LIBSDMD): $(LIBSMD_SRC)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/sdmd.o $(LIBSMD_SRC) $(ARCHFLAG) $(LIBSDMD_IMPORTS)
	ar rcs $(LIBSDMD) obj/sdmd.o
