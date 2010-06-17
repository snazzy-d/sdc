all:
	dmd -ofsdc.bin src/sdc/*.d src/sdc/ast/*.d src/sdc/parser/*.d src/sdc/asttojson/*.d src/sdc/semantic/*.d src/sdc/asttosemantic/*.d import/libdjson/json.d -w -debug -gc -Iimport

