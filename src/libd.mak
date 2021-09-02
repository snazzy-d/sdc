LIBD_SRC_D = $(wildcard src/d/*.d)
LIBD_SRC_UTIL = $(wildcard src/util/*.d)
LIBD_SRC_COMMON = $(wildcard src/d/common/*.d)
LIBD_SRC_AST = $(wildcard src/d/ast/*.d)
LIBD_SRC_IR = $(wildcard src/d/ir/*.d)
LIBD_SRC_PARSER = $(wildcard src/d/parser/*.d)
LIBD_SRC_SEMANTIC = $(wildcard src/d/semantic/*.d)
LIBD_SRC_ALL = $(LIBD_SRC_D) $(LIBD_SRC_COMMON) \
               $(LIBD_SRC_UTIL) $(LIBD_SRC_AST) $(LIBD_SRC_IR) \
               $(LIBD_SRC_PARSER) $(LIBD_SRC_SEMANTIC)

LIBD_SEMANTIC_OBJ = $(LIBD_SRC_SEMANTIC:src/d/semantic/%.d=obj/semantic/%.o)

ifdef SEPARATE_LIBD_COMPILATION
	LIBD_DEP_ALL = obj/d.o obj/util.o obj/common.o obj/ast.o obj/ir.o obj/parser.o $(LIBD_SEMANTIC_OBJ)
else
	LIBD_DEP_ALL = obj/libd.o
endif

LIBD = lib/libd.a

$(LIBD): $(LIBD_DEP_ALL)
	@mkdir -p lib
	ar rcs $(LIBD) $^

obj/libd.o: $(LIBD_SRC_ALL)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_ALL) -makedeps="$@.deps" $(DFLAGS)

obj/d.o: $(LIBD_SRC_D)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_D) -makedeps="$@.deps" $(DFLAGS)

check-libd-d: $(LIBD_SRC_D)
	$(RDMD) $(DFLAGS) -unittest -i $(addprefix --extra-file=, $^) --eval="/* Do nothing */"

obj/util.o: $(LIBD_SRC_UTIL)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_UTIL) -makedeps="$@.deps" $(DFLAGS)

check-libd-util: $(LIBD_SRC_UTIL)
	$(RDMD) $(DFLAGS) -unittest -i $(addprefix --extra-file=, $^) --eval="/* Do nothing */"

obj/common.o: $(LIBD_SRC_COMMON)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_COMMON) -makedeps="$@.deps" $(DFLAGS)

check-libd-common: $(LIBD_SRC_COMMON)
	$(RDMD) $(DFLAGS) -unittest -i $(addprefix --extra-file=, $^) --eval="/* Do nothing */"

obj/ast.o: $(LIBD_SRC_AST)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_AST) -makedeps="$@.deps" $(DFLAGS)

check-libd-ast: $(LIBD_SRC_AST)
	$(RDMD) $(DFLAGS) -unittest -i $(addprefix --extra-file=, $^) --eval="/* Do nothing */"

obj/ir.o: $(LIBD_SRC_IR)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_IR) -makedeps="$@.deps" $(DFLAGS)

check-libd-ir: $(LIBD_SRC_IR)
	$(RDMD) $(DFLAGS) -unittest -i $(addprefix --extra-file=, $^) --eval="/* Do nothing */"

obj/parser.o: $(LIBD_SRC_PARSER)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_PARSER) -makedeps="$@.deps" $(DFLAGS)

check-libd-parser: $(LIBD_SRC_PARSER)
	$(RDMD) $(DFLAGS) -unittest -i $(addprefix --extra-file=, $^) --eval="/* Do nothing */"

obj/semantic/%.o: src/d/semantic/%.d
	@mkdir -p obj/semantic
	$(DMD) -c -of"$@" "$<" -makedeps="$@.deps" $(DFLAGS)

check-libd-semantic: $(LIBD_SRC_SEMANTIC)
	$(RDMD) $(DFLAGS) -unittest -i $(addprefix --extra-file=, $^) --eval="/* Do nothing */"

check-libd: check-libd-d check-libd-util check-libd-common check-libd-ast check-libd-ir check-libd-parser check-libd-semantic
.PHONY: check-libd-d check-libd-util check-libd-common check-libd-ast check-libd-ir check-libd-parser check-libd-semantic

check: check-libd
