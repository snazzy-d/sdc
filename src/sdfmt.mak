# Common definitions

LIBSDFMT_SRC = $(wildcard src/format/*.d)

SDFMT = bin/sdfmt

LIBSDFMT = lib/libsdfmt.a

SDC_IMPORTS = -Isrc -Iimport

$(LIBSDFMT): $(LIBSDFMT_SRC)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/format.o -makedeps="$@.deps" $(LIBSDFMT_SRC) $(DFLAGS) $(SDC_IMPORTS)
	ar rcs $(LIBSDFMT) obj/format.o

$(SDFMT): obj/driver/sdfmt.o $(LIBSDFMT) $(LIBSOURCE)
	@mkdir -p bin
	$(GCC) -o "$@" $^ $(ARCHFLAG) $(LDFLAGS)
