LIBSOURCE_SRC = $(wildcard src/source/*.d) $(wildcard src/source/util/*.d)

LIBSOURCE = lib/libsource.a

obj/libsource.o: $(LIBSOURCE_SRC)
	@mkdir -p lib obj
	$(DMD) -c -of"$@" $(LIBSOURCE_SRC) -makedeps="$@.deps" $(DFLAGS)

$(LIBSOURCE): obj/libsource.o
	ar rcs $(LIBSOURCE) obj/libsource.o

check-source: $(LIBSOURCE_SRC)
	$(RDMD) $(DFLAGS) -unittest -i $(addprefix --extra-file=, $^) --eval="/* Do nothing */"

check: check-source
.PHONY: check-source
