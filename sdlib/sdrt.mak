LIBSDRT_D_SRC = $(wildcard sdlib/d/*.d)
LIBSDRT_DMD_SRC = $(wildcard sdlib/dmd/*.d)
LIBSDRT_GC_SRC = $(wildcard sdlib/d/gc/*.d)
LIBSDRT_RT_SRC = $(wildcard sdlib/d/rt/*.d)
LIBSDRT_SDC_SRC = $(wildcard sdlib/sdc/*.d)
LIBSDRT_STDC_SRC = $(wildcard sdlib/core/stdc/*.d)
LIBSDRT_SYNC_SRC = $(wildcard sdlib/d/sync/*.d) \
	$(wildcard sdlib/d/sync/futex/*.d)

LIBSDRT_LINUX_SRC = $(wildcard sdlib/sys/linux/*.d)

LIBSDRT_OSX_SRC_C = $(wildcard sdlib/sys/osx/*.c)
LIBSDRT_OSX_SRC_D = $(wildcard sdlib/sys/osx/*.d)
LIBSDRT_OSX_OBJ_C = $(LIBSDRT_OSX_SRC_C:sdlib/sys/osx/%.c=obj/osx/%.o)
LIBSDRT_OSX_OBJ_D = $(LIBSDRT_OSX_SRC_D:sdlib/sys/osx/%.d=obj/osx/%.o)
LIBSDRT_OSX_OBJ = $(LIBSDRT_OSX_OBJ_C) $(LIBSDRT_OSX_OBJ_D)

LIBSDRT_X64_SRC = $(wildcard sdlib/sys/x64/*.asm)
LIBSDRT_X64_OBJ = $(LIBSDRT_X64_SRC:sdlib/sys/x64/%.asm=obj/x64/%.o)

COMMON_LIB_DEPS = obj/object.o obj/sdlib/gc.o obj/sdlib/rt.o obj/sdlib/stdc.o \
	obj/sdlib/sync.o $(LIBSDRT_X64_OBJ)
LIBSDRT_DEPS = $(COMMON_LIB_DEPS) obj/sdlib/d.o obj/sdlib/sdc.o
LIBDMDALLOC_DEPS = $(COMMON_LIB_DEPS) obj/sdlib/dmd.o

ifeq ($(PLATFORM),Linux)
	LIBSDRT_DEPS += obj/sdlib/linux.o
endif

ifeq ($(PLATFORM),Darwin)
	LIBSDRT_DEPS += $(LIBSDRT_OSX_OBJ)
endif

LIBSDRT = lib/libsdrt.a
LIBDMDALLOC = lib/libdmdalloc.a

SDFLAGS ?=
LIBSDRT_IMPORTS = -Isdlib

obj/object.o: sdlib/object.d $(SDLIB_DEPS)
	@mkdir -p obj
	$(SDC) -c -o $@ $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/sdlib/d.o: $(LIBSDRT_D_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/sdlib
	$(SDC) -c -o $@ $(LIBSDRT_D_SRC) $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/sdlib/gc.o: $(LIBSDRT_GC_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/sdlib
	$(SDC) -c -o $@ $(LIBSDRT_GC_SRC) $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/sdlib/rt.o: $(LIBSDRT_RT_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/sdlib
	$(SDC) -c -o $@ $(LIBSDRT_RT_SRC) $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/sdlib/sdc.o: $(LIBSDRT_SDC_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/sdlib
	$(SDC) -c -o $@ $(LIBSDRT_SDC_SRC) $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/sdlib/stdc.o: $(LIBSDRT_STDC_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/sdlib
	$(SDC) -c -o $@ $(LIBSDRT_STDC_SRC) $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/sdlib/sync.o: $(LIBSDRT_SYNC_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/sdlib
	$(SDC) -c -o $@ $(LIBSDRT_SYNC_SRC) $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/sdlib/linux.o: $(LIBSDRT_LINUX_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/sdlib
	$(SDC) -c -o $@ $(LIBSDRT_LINUX_SRC) $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/sdlib/dmd.o: $(LIBSDRT_DMD_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/sdlib
	$(SDC) -c -o $@ $(LIBSDRT_DMD_SRC) $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/osx/%.o: sdlib/sys/osx/%.c $(LIBSDRT_OSX_SRC_C) $(SDLIB_DEPS)
	@mkdir -p obj/osx
	clang -c -o $@ $<

obj/osx/%.o: sdlib/sys/osx/%.d $(LIBSDRT_OSX_SRC_D) $(SDLIB_DEPS)
	@mkdir -p obj/osx
	$(SDC) -c -o $@ $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/x64/%.o: sdlib/sys/x64/%.asm $(LIBSDRT_X64_SRC)
	@mkdir -p obj/x64
	$(AS) -o $@ $< $(ASFLAGS)

$(LIBSDRT): $(LIBSDRT_DEPS)
	@mkdir -p lib
	ar rcs "$@" $^

$(LIBDMDALLOC): $(LIBDMDALLOC_DEPS)
	@mkdir -p lib
	ar rcs "$@" $^

# Phobos
PHOBOS_SRC = $(wildcard sdlib/std/*.d)
PHOBOS_OBJ = $(PHOBOS_SRC:sdlib/std/%.d=obj/phobos/%.o)

PHOBOS = lib/libphobos.a

obj/phobos/%.o: sdlib/std/%.d $(PHOBOS_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/phobos
	$(SDC) -c -o $@ $< $(SDFLAGS)

$(PHOBOS): $(PHOBOS_OBJ)
	@mkdir -p lib obj/phobos
	ar rcs "$@" $^

# Tools
TOOLS_SRC = $(wildcard sdlib/tools/*.d)
ALL_TOOLS = $(TOOLS_SRC:sdlib/tools/%.d=bin/tools/%)

bin/tools/%: sdlib/tools/%.d $(SDC) $(LIBSDRT) $(PHOBOS)
	@mkdir -p bin/tools
	$(SDC) -o "$@" $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

# Tests
CHECK_LIBSDRT_GC = $(LIBSDRT_GC_SRC:sdlib/d/gc/%.d=check-sdlib-gc-%)
CHECK_LIBSDRT_RT = $(LIBSDRT_RT_SRC:sdlib/d/rt/%.d=check-sdlib-rt-%)
CHECK_LIBSDRT_STDC = $(LIBSDRT_STDC_SRC:sdlib/core/stdc/%.d=check-sdlib-stdc-%)
CHECK_LIBSDRT_SYNC = $(LIBSDRT_SYNC_SRC:sdlib/d/sync/%.d=check-sdlib-sync-%)

check-sdlib-gc-%: sdlib/d/gc/%.d $(SDUNIT)
	$(SDUNIT) $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

check-sdlib-rt-%: sdlib/d/rt/%.d $(SDUNIT)
	$(SDUNIT) $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

check-sdlib-stdc-%: sdlib/core/stdc/%.d $(SDUNIT)
	$(SDUNIT) $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

check-sdlib-sync-%: sdlib/d/sync/%.d $(SDUNIT)
	$(SDUNIT) $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

check-sdlib-sync-futex/%: sdlib/d/sync/futex/%.d $(SDUNIT)
	$(SDUNIT) $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

check-sdlib-gc: $(CHECK_LIBSDRT_GC)
check-sdlib-rt: $(CHECK_LIBSDRT_RT)
check-sdlib-stdc: $(CHECK_LIBSDRT_STDC)
check-sdlib-sync: $(CHECK_LIBSDRT_SYNC)

check-sdlib: check-sdlib-gc check-sdlib-rt check-sdlib-stdc check-sdlib-sync

check: check-sdlib
.PHONY: check-sdlib check-sdlib-gc check-sdlib-rt check-sdlib-stdc check-sdlib-sync
