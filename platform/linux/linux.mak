PLATFORM_IMPORTS += platform/linux/imports
LIBSDRT_PLATFORM_IMPORTS += platform/linux/sdlib

LIBSDRT_PLATFORM_SRC = $(wildcard platform/linux/sdlib/d/sync/*.d) $(wildcard platform/linux/sdlib/d/gc/*.d)
