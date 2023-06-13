LIBUTIL_SRC = $(wildcard src/util/*.d)

LIBUTIL = lib/libutil.a

obj/util.o: $(LIBUTIL_SRC)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBUTIL_SRC) -makedeps="$@.deps" $(DFLAGS)

$(LIBUTIL): obj/util.o
	ar rcs "$@" $^

check-util: $(LIBUTIL_SRC)
	$(RDMD) $(DFLAGS) -unittest -i $(addprefix --extra-file=, $^) --eval="assert(true)"

check: check-util
.PHONY: check-util
