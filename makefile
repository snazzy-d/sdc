all:
	dmd -ofsdc.bin src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/asttojson/*.d src/sdc/gen/*.d src/sdc/gen/llvm/*.d src/sdc/extract/*.d import/libdjson/json.d -w -debug -gc -Iimport

