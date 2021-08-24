# Common definitions

LIBD_SRC_D = $(wildcard src/d/*.d)
LIBD_SRC_UTIL = $(wildcard src/util/*.d)
LIBD_SRC_CONTEXT = $(wildcard src/d/context/*.d)
LIBD_SRC_COMMON = $(wildcard src/d/common/*.d)
LIBD_SRC_AST = $(wildcard src/d/ast/*.d)
LIBD_SRC_IR = $(wildcard src/d/ir/*.d)
LIBD_SRC_PARSER = $(wildcard src/d/parser/*.d)
LIBD_SRC_SEMANTIC = $(wildcard src/d/semantic/*.d)
LIBD_SRC_ALL = $(LIBD_SRC_D) $(LIBD_SRC_CONTEXT) $(LIBD_SRC_COMMON) \
               $(LIBD_SRC_UTIL) $(LIBD_SRC_AST) $(LIBD_SRC_IR) \
               $(LIBD_SRC_PARSER) $(LIBD_SRC_SEMANTIC)

LIBD_SEMANTIC_OBJ = $(LIBD_SRC_SEMANTIC:src/d/semantic/%.d=obj/semantic/%.o)

ifdef SEPARATE_LIBD_COMPILATION
	LIBD_DEP_ALL = obj/d.o obj/util.o obj/context.o obj/common.o obj/ast.o obj/ir.o obj/parser.o $(LIBD_SEMANTIC_OBJ)
else
	LIBD_DEP_ALL = obj/libd.o
endif

LIBD = lib/libd.a

LIBD_IMPORTS = -Isrc

$(LIBD): $(LIBD_DEP_ALL)
	@mkdir -p lib
	ar rcs $(LIBD) $^

obj/libd.o: $(LIBD_SRC_ALL)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_ALL) -makedeps="$@.deps" $(DFLAGS) $(LIBD_IMPORTS)

obj/d.o: $(LIBD_SRC_D)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_D) -makedeps="$@.deps" $(DFLAGS) $(LIBD_IMPORTS)

obj/util.o: $(LIBD_SRC_UTIL)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_UTIL) -makedeps="$@.deps" $(DFLAGS) $(LIBD_IMPORTS)

obj/context.o: $(LIBD_SRC_CONTEXT)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_CONTEXT) -makedeps="$@.deps" $(DFLAGS) $(LIBD_IMPORTS)

obj/common.o: $(LIBD_SRC_COMMON)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_COMMON) -makedeps="$@.deps" $(DFLAGS) $(LIBD_IMPORTS)

obj/ast.o: $(LIBD_SRC_AST)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_AST) -makedeps="$@.deps" $(DFLAGS) $(LIBD_IMPORTS)

obj/ir.o: $(LIBD_SRC_IR)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_IR) -makedeps="$@.deps" $(DFLAGS) $(LIBD_IMPORTS)

obj/parser.o: $(LIBD_SRC_PARSER)
	@mkdir -p obj
	$(DMD) -c -of"$@" $(LIBD_SRC_PARSER) -makedeps="$@.deps" $(DFLAGS) $(LIBD_IMPORTS)

obj/semantic/%.o: src/d/semantic/%.d
	@mkdir -p obj/semantic
	$(DMD) -c -of"$@" "$<" -makedeps="$@.deps" $(DFLAGS) $(LIBD_IMPORTS)
