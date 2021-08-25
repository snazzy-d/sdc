# Common definitions

LIBSOURCE_SRC = $(wildcard src/source/*.d) $(wildcard src/source/util/*.d)

LIBSOURCE = lib/libsource.a

$(LIBSOURCE): $(LIBSOURCE_SRC)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/libsource.o $(LIBSOURCE_SRC) -makedeps="$@.deps" $(DFLAGS)
	ar rcs $(LIBSOURCE) obj/libsource.o

check-source: $(LIBSOURCE_SRC)
	$(DMD) $(DFLAGS) -main -unittest -i -run $(LIBSOURCE_SRC)

check: check-source
.PHONY: check-source
