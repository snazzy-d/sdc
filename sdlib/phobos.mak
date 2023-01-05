PHOBOS_SRC = $(wildcard sdlib/std/*.d)
PHOBOS_OBJ = $(PHOBOS_SRC:sdlib/std/%.d=obj/phobos/%.o)

PHOBOS = lib/libphobos.a

obj/phobos/%.o: sdlib/std/%.d $(PHOBOS_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/phobos
	$(SDC) -c -o $@ $< $(SDFLAGS)

$(PHOBOS): $(PHOBOS_OBJ)
	@mkdir -p lib obj/phobos
	ar rcs "$@" $^
