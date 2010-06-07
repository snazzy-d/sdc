all:
	dmd -ofsdc.bin src/sdc/*.d src/sdc/ast/*.d import/libdjson/json.d -w -debug -gc -Iimport

