# Common definitions

LIBSOURCE_SRC = $(wildcard src/source/*.d) $(wildcard src/source/util/*.d)

LIBSOURCE = lib/libsource.a

LIBSOURCE_IMPORTS = -Isrc

$(LIBSOURCE): $(LIBSOURCE_SRC)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/libsource.o $(LIBSOURCE_SRC) -makedeps="$@.deps" $(DFLAGS) $(LIBSOURCE_IMPORTS)
	ar rcs $(LIBSOURCE) obj/libsource.o
