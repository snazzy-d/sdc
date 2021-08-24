# Common definitions

LIBSDC_SRC = $(wildcard src/sdc/*.d) $(wildcard src/sdc/util/*.d)

DRIVER_SRC = $(wildcard src/driver/*.d)
DRIVER_OBJ = $(DRIVER_SRC:src/driver/%.d=obj/driver/%.o)
ALL_EXECUTABLES = $(DRIVER_SRC:src/driver/%.d=bin/%)

SDC = bin/sdc
SDUNIT = bin/sdunit

LIBSDC = lib/libsdc.a

include src/libd.mak
include src/libd-llvm.mak
include src/libsource.mak

SDC_IMPORTS = -Isrc -Iimport

$(LIBSDC): $(LIBSDC_SRC)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/sdc.o -makedeps="$@.deps" $(LIBSDC_SRC) $(DFLAGS) $(SDC_IMPORTS)
	ar rcs $(LIBSDC) obj/sdc.o

obj/driver/%.o: src/driver/%.d
	@mkdir -p obj/driver
	$(DMD) -c -of"$@" "$<" -makedeps="$@.deps" $(DFLAGS) $(SDC_IMPORTS)

$(SDC): obj/driver/sdc.o $(LIBSDC) $(LIBD) $(LIBD_LLVM) $(LIBSDMD) $(LIBSOURCE)
	@mkdir -p bin
	$(GCC) -o "$@" $+ $(ARCHFLAG) $(LDFLAGS)

$(SDUNIT): obj/driver/sdunit.o $(LIBSDC) $(LIBD) $(LIBD_LLVM) $(LIBSDMD) $(LIBSOURCE)
	@mkdir -p bin
	$(GCC) -o "$@" $+ $(ARCHFLAG) $(LDFLAGS)

bin/sdc.conf:
	@mkdir -p bin
	printf "{\n\t\"includePath\": [\"$(PWD)/sdlib\", \".\"],\n\t\"libPath\": [\"$(PWD)/lib\"],\n}\n" > $@
