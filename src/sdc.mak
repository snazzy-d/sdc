# Common definitions

LIBSDC_SRC = $(wildcard src/sdc/*.d) $(wildcard src/sdc/util/*.d) $(wildcard src/sdc/format/*.d)

LIBSDC_DEP = $(LIBSDC_SRC) $(LIBD_SRC_ALL) $(LIBD_LLVM_SRC)

DRIVER_SRC = $(wildcard src/driver/*.d)
DRIVER_OBJ = $(DRIVER_SRC:src/driver/%.d=obj/driver/%.o)
ALL_EXECUTABLES = $(DRIVER_SRC:src/driver/%.d=bin/%)

SDC = bin/sdc
SDUNIT = bin/sdunit
SDFMT = bin/sdfmt

LIBSDC = lib/libsdc.a

include src/libd-llvm.mak

SDC_IMPORTS = -Isrc -Iimport

$(LIBSDC): $(LIBSDC_SRC) $(LIBSDC_DEP)
	@mkdir -p lib obj
	$(DMD) -c -ofobj/sdc.o $(LIBSDC_SRC) $(DFLAGS) $(SDC_IMPORTS)
	ar rcs $(LIBSDC) obj/sdc.o

obj/driver/%.o: src/driver/%.d $(LIBSDC_SRC) $(LIBD_SRC) $(LIBD_LLVM_SRC)
	@mkdir -p obj/driver
	$(DMD) -c -of$@ $< $(DFLAGS) $(SDC_IMPORTS)

# SDFMT only require libd, but there are no easy way to do this
# within the current makefiles.
bin/%: obj/driver/%.o $(LIBSDC) $(LIBD) $(LIBD_LLVM) $(LIBSDMD)
	@mkdir -p bin
	$(GCC) -o $@ $< $(ARCHFLAG) $(LDFLAGS)

bin/sdc.conf:
	@mkdir -p bin
	printf "{\n\t\"includePath\": [\"$(PWD)/sdlib\", \".\"],\n\t\"libPath\": [\"$(PWD)/lib\"],\n}\n" > $@
