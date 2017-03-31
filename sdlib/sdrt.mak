# Common definitions

LIBSDRT_GC_SRC = $(wildcard sdlib/d/gc/*.d)
LIBSDRT_STDC_SRC = $(wildcard sdlib/core/stdc/*.d)
LIBSDRT_RT_SRC = $(wildcard sdlib/d/rt/*.d)

LIBSDRT_GC_OBJ = $(LIBSDRT_GC_SRC:sdlib/d/gc/%.d=obj/gc/%.o)
LIBSDRT_STDC_OBJ = $(LIBSDRT_STDC_SRC:sdlib/core/stdc/%.d=obj/stdc/%.o)
LIBSDRT_RT_OBJ = $(LIBSDRT_RT_SRC:sdlib/d/rt/%.d=obj/rt/%.o)

LIBSDRT_LINUX_SRC = $(wildcard sdlib/sys/linux/*.d)
LIBSDRT_LINUX_OBJ = $(LIBSDRT_LINUX_SRC:sdlib/sys/linux/%.d=obj/linux/%.o)

LIBSDRT_OSX_SRC_C = $(wildcard sdlib/sys/osx/*.c)
LIBSDRT_OSX_SRC_D = $(wildcard sdlib/sys/osx/*.d)
LIBSDRT_OSX_OBJ_C = $(LIBSDRT_OSX_SRC_C:sdlib/sys/osx/%.c=obj/osx/%.o)
LIBSDRT_OSX_OBJ_D = $(LIBSDRT_OSX_SRC_D:sdlib/sys/osx/%.d=obj/osx/%.o)
LIBSDRT_OSX_OBJ = $(LIBSDRT_OSX_OBJ_C) $(LIBSDRT_OSX_OBJ_D)

LIBSDRT_X64_SRC = $(wildcard sdlib/sys/x64/*.asm)
LIBSDRT_X64_OBJ = $(LIBSDRT_X64_SRC:sdlib/sys/x64/%.asm=obj/x64/%.o)

LIBSDRT_DEPS = obj/object.o $(LIBSDRT_GC_OBJ) $(LIBSDRT_STDC_OBJ) \
	$(LIBSDRT_RT_OBJ) $(LIBSDRT_X64_OBJ)

ifeq ($(PLATFORM),Linux)
	LIBSDRT_DEPS += $(LIBSDRT_LINUX_OBJ)
endif

ifeq ($(PLATFORM),Darwin)
	LIBSDRT_DEPS += $(LIBSDRT_OSX_OBJ)
endif

LIBSDRT = lib/libsdrt.a

SDFLAGS ?=
LIBSDRT_IMPORTS = -Isdlib

obj/object.o: sdlib/object.d $(SDLIB_DEPS)
	@mkdir -p obj
	$(SDC) -c -o $@ $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/gc/%.o: sdlib/d/gc/%.d $(LIBSDRT_GC_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/gc
	$(SDC) -c -o $@ $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/stdc/%.o: sdlib/core/stdc/%.d $(LIBSDRT_STDC_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/stdc
	$(SDC) -c -o $@ $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/rt/%.o: sdlib/d/rt/%.d $(LIBSDRT_RT_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/rt
	$(SDC) -c -o $@ $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/linux/%.o: sdlib/sys/linux/%.d $(LIBSDRT_LINUX_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/linux
	$(SDC) -c -o $@ $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/osx/%.o: sdlib/sys/osx/%.c $(LIBSDRT_OSX_SRC_C) $(SDLIB_DEPS)
	@mkdir -p obj/osx
	clang -c -o $@ $<

obj/osx/%.o: sdlib/sys/osx/%.d $(LIBSDRT_OSX_SRC_D) $(SDLIB_DEPS)
	@mkdir -p obj/osx
	$(SDC) -c -o $@ $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

obj/x64/%.o: sdlib/sys/x64/%.asm $(LIBSDRT_X64_SRC) $(SDLIB_DEPS)
	@mkdir -p obj/x64
	$(NASM) -o $@ $< $(NASMFLAGS)

$(LIBSDRT): $(LIBSDRT_DEPS)
	@mkdir -p lib
	ar rcs $(LIBSDRT) $^
