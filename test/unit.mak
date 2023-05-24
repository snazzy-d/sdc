TEST_UNIT_SRC = $(wildcard test/unit/*.d)
CHECK_UNIT = $(TEST_UNIT_SRC:test/unit/%.d=check-unit-%)

check-unit-%: test/unit/%.d $(SDUNIT)
	$(SDUNIT) $< $(SDFLAGS) $(LIBSDRT_IMPORTS)

check-unit: $(CHECK_UNIT)

check: check-unit
.PHONY: check-unit
