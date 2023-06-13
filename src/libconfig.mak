LIBCONFIG_SRC = $(wildcard src/config/*.d)

LIBCONFIG = lib/libconfig.a

obj/config.o: $(LIBCONFIG_SRC)
	@mkdir -p lib obj
	$(DMD) -c -of"$@" $(LIBCONFIG_SRC) -makedeps="$@.deps" $(DFLAGS)

$(LIBCONFIG): obj/config.o
	ar rcs "$@" $^

check-config: $(LIBCONFIG_SRC)
	$(RDMD) $(DFLAGS) -unittest -i $(addprefix --extra-file=, $^) --eval="assert(true)"

check: check-config
.PHONY: check-config
