all:
	dmd -ofsdc.bin src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d import/libdjson/json.d -w -debug -gc -Iimport

