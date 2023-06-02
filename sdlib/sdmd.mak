LIBSMD_SRC = sdlib/d/rt/eh.d sdlib/d/rt/object.d sdlib/d/rt/dwarf.d

LIBSDMD = lib/libsdmd.a

SDFLAGS ?=

# XXX: This kind of stunt would be better suited for the configure
# step, but we don't have one.
NATIVE_OBJECT_D = $(shell echo "int dummy;" | $(DMD) -v - -of/dev/null 2> /dev/null | sed -ne 's/^import\s*object\s*(\(.*\))/\1/p')
NATIVE_DRUNTIME ?= $(dir $(NATIVE_OBJECT_D))
LIBSDMD_IMPORTS = -I$(NATIVE_DRUNTIME) -Isdlib

obj/sdmd.o: $(LIBSMD_SRC)
	@mkdir -p lib obj
	$(DMD) -c -of"$@" $(LIBSMD_SRC) -makedeps="$@.deps" $(ARCHFLAG) $(LIBSDMD_IMPORTS)

$(LIBSDMD): obj/sdmd.o
	ar rcs "$@" $^
