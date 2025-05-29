# Platform import to use for libsdrt
PLATFORM_IMPORTS =

# Platform objects to link into libsdrt
LIBSDRT_PLATFORM_OBJ =

# Platform objects to link into libsdmd
LIBSDMD_PLATFORM_OBJ =

# Platform C source and object files.
PLATFORM_C_SRC =
PLATFORM_C_OBJ =

# Platform assempbly source and object files.
PLATFORM_ASM_SRC =
PLATFORM_ASM_OBJ =

ifeq ($(PLATFORM),Linux)
	include platform/linux/linux.mak
else ifeq ($(PLATFORM),Darwin)
	include platform/osx/osx.mak
endif

ifeq ($(ARCH),x86_64)
	include platform/x64/x64.mak
else ifeq ($(ARCH),arm64)
	include platform/arm64/arm64.mak
endif

# FIXME: depfiles.
$(PLATFORM_C_OBJ): obj/%.o: platform/%.c
	@mkdir -p $(@D)
	clang -c -o $@ $<

$(PLATFORM_ASM_OBJ): obj/%.o: platform/%.asm
	@mkdir -p $(@D)
	$(AS) -o $@ $< $(ASFLAGS)
