LIBSDC_SRC = $(wildcard src/sdc/*.d)

DRIVER_SRC = $(wildcard src/driver/*.d)
DRIVER_OBJ = $(DRIVER_SRC:src/driver/%.d=obj/driver/%.o)
ALL_EXECUTABLES = $(DRIVER_SRC:src/driver/%.d=bin/%)

SDC = bin/sdc
SDUNIT = bin/sdunit

LIBSDC = lib/libsdc.a

include src/libd.mak
include src/libd-llvm.mak
include src/libutil.mak
include src/libsource.mak
include src/libconfig.mak

include platform/platform.mak
include sdlib/sdmd.mak

obj/sdc.o: $(LIBSDC_SRC)
	@mkdir -p lib obj
	$(DMD) -c -of"$@" $(LIBSDC_SRC) -makedeps="$@.deps" $(DFLAGS) $(LIBD_LLVM_IMPORTS)

$(LIBSDC): obj/sdc.o
	ar rcs "$@" $^

obj/driver/%.o: src/driver/%.d
	@mkdir -p obj/driver
	$(DMD) -c -of"$@" "$<" -makedeps="$@.deps" $(DFLAGS) $(LIBD_LLVM_IMPORTS)

$(SDC): obj/driver/sdc.o $(LIBSDC) $(LIBD) $(LIBD_LLVM) $(LIBSDMD) $(LIBCONFIG) $(LIBSOURCE) $(LIBUTIL)
	@mkdir -p bin
	$(DMD) -of"$@" $+ $(DFLAGS) $(addprefix -Xcc=,$(LDFLAGS)) $(addprefix -Xcc=,$(LDFLAGS_LLVM))

$(SDUNIT): obj/driver/sdunit.o $(LIBSDC) $(LIBD) $(LIBD_LLVM) $(LIBSDMD) $(LIBCONFIG) $(LIBSOURCE) $(LIBUTIL)
	@mkdir -p bin
	$(DMD) -of"$@" $+ $(DFLAGS) $(addprefix -Xcc=,$(LDFLAGS)) $(addprefix -Xcc=,$(LDFLAGS_LLVM))

IMPORTS_JSON_SEPARATOR = "\", \"$(PWD)/"
SDCONFIG_IMPORTS = "[\"$(PWD)/$(addsuffix $(IMPORTS_JSON_SEPARATOR), $(PLATFORM_IMPORTS))sdlib\"]"

bin/sdconfig:
	@mkdir -p bin
	printf "{\n\t\"includePaths\": $(SDCONFIG_IMPORTS),\n\t\"libPaths\": [\"$(PWD)/lib\"],\n}\n" > $@

SDLIB_DEPS = $(SDC) bin/sdconfig

include sdlib/sdrt.mak

check-sdc: $(SDC) bin/sdconfig $(LIBSDRT) $(PHOBOS)
	test/runner/runner.d

check: check-sdc
.PHONY: check-sdc
