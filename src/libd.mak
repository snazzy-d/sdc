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

LIBD_DEP_D = $(LIBD_SRC_D)
LIBD_DEP_UTIL = $(LIBD_SRC_UTIL)
LIBD_DEP_CONTEXT = $(LIBD_SRC_CONTEXT)
LIBD_DEP_COMMON = $(LIBD_SRC_COMMON) $(LIBD_DEP_CONTEXT) $(LIBD_DEP_D)
LIBD_DEP_AST = $(LIBD_SRC_AST) $(LIBD_DEP_COMMON)
LIBD_DEP_IR = $(LIBD_SRC_IR) $(LIBD_DEP_COMMON)
LIBD_DEP_PARSER = $(LIBD_SRC_PARSER) $(LIBD_DEP_AST)
LIBD_DEP_SEMANTIC = $(LIBD_SRC_SEMANTIC) $(LIBD_DEP_AST) $(LIBD_DEP_IR) \
                    $(LIBD_DEP_PARSER) $(LIBD_DEP_UTIL)

LIBD_SEMANTIC_OBJ = $(LIBD_SRC_SEMANTIC:src/d/semantic/%.d=obj/semantic/%.o)

ifdef SEPARATE_LIBD_COMPILATION
	LIBD_DEP_ALL = obj/d.o obj/util.o obj/context.o obj/common.o obj/ast.o obj/ir.o obj/parser.o $(LIBD_SEMANTIC_OBJ)
else
	LIBD_DEP_ALL = obj/libd.o
endif

LIBD = lib/libd.a

LIBD_IMPORTS = -Isrc

all: $(ALL_TARGET)

$(LIBD): $(LIBD_DEP_ALL)
	@mkdir -p lib
	ar rcs $(LIBD) $^

obj/libd.o: $(LIBD_SRC_ALL)
	@mkdir -p obj
	$(DMD) -c -of$@ $^ $(DFLAGS) $(LIBD_IMPORTS)

obj/d.o: $(LIBD_DEP_D)
	@mkdir -p obj
	$(DMD) -c -of$@ $(LIBD_SRC_D) $(DFLAGS) $(LIBD_IMPORTS)

obj/util.o: $(LIBD_DEP_UTIL)
	@mkdir -p obj
	$(DMD) -c -of$@ $(LIBD_SRC_UTIL) $(DFLAGS) $(LIBD_IMPORTS)

obj/context.o: $(LIBD_DEP_CONTEXT)
	@mkdir -p obj
	$(DMD) -c -of$@ $(LIBD_SRC_CONTEXT) $(DFLAGS) $(LIBD_IMPORTS)

obj/common.o: $(LIBD_DEP_COMMON)
	@mkdir -p obj
	$(DMD) -c -of$@ $(LIBD_SRC_COMMON) $(DFLAGS) $(LIBD_IMPORTS)

obj/ast.o: $(LIBD_DEP_AST)
	@mkdir -p obj
	$(DMD) -c -of$@ $(LIBD_SRC_AST) $(DFLAGS) $(LIBD_IMPORTS)

obj/ir.o: $(LIBD_DEP_IR)
	@mkdir -p obj
	$(DMD) -c -of$@ $(LIBD_SRC_IR) $(DFLAGS) $(LIBD_IMPORTS)

obj/parser.o: $(LIBD_DEP_PARSER)
	@mkdir -p obj
	$(DMD) -c -of$@ $(LIBD_SRC_PARSER) $(DFLAGS) $(LIBD_IMPORTS)

obj/semantic/%.o: src/d/semantic/%.d $(LIBD_DEP_SEMANTIC)
	@mkdir -p obj/semantic
	$(DMD) -c -of$@ $< $(DFLAGS) $(LIBD_IMPORTS)
