LIBCONFIG_SRC = $(wildcard src/config/*.d)

LIBCONFIG = lib/libconfig.a

$(LIBCONFIG): $(LIBCONFIG_SRC)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/libconfig.o $(LIBCONFIG_SRC) -makedeps="$@.deps" $(DFLAGS)
	ar rcs $(LIBCONFIG) obj/libconfig.o

check-config: $(LIBCONFIG_SRC)
	$(DMD) $(DFLAGS) -main -unittest -i -run $(LIBCONFIG_SRC)

check: check-config
.PHONY: check-config
