PLATFORM_IMPORTS += platform/osx/imports

PLATFORM_OSX_C_SRC = $(wildcard platform/osx/*.c)
PLATFORM_C_SRC += $(PLATFORM_OSX_C_SRC)

PLATFORM_OSX_C_OBJ = $(PLATFORM_OSX_C_SRC:platform/%.c=obj/%.o)
PLATFORM_C_OBJ += $(PLATFORM_OSX_C_OBJ)

# Add the objects to expected variables.
LIBSDRT_PLATFORM_OBJ += $(PLATFORM_OSX_C_OBJ)
