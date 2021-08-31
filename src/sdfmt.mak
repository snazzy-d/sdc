LIBSDFMT_SRC = $(wildcard src/format/*.d)

SDFMT = bin/sdfmt

LIBSDFMT = lib/libsdfmt.a

$(LIBSDFMT): $(LIBSDFMT_SRC)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/format.o -makedeps="$@.deps" $(LIBSDFMT_SRC) $(DFLAGS)
	ar rcs $(LIBSDFMT) obj/format.o

$(SDFMT): obj/driver/sdfmt.o $(LIBSDFMT) $(LIBSOURCE)
	@mkdir -p bin
	$(GCC) -o "$@" $^ $(ARCHFLAG) $(LDFLAGS)

check-libfmt: $(LIBSDFMT_SRC)
	$(DMD) $(DFLAGS) -main -unittest -i -run $(LIBSDFMT_SRC)

check-sdfmt: $(SDFMT)
	test/runner/checkformat.d

check: check-libfmt check-sdfmt
.PHONY: check-libfmt check-sdfmt
