all:
	dmd -ofsdc.bin src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/asttojson/*.d import/libdjson/json.d -w -debug -gc -Iimport

