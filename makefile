all:
	dmd -ofsdc src/sdc/*.d src/sdc/ast/*.d import/libdjson/json.d -w -debug -gc -Iimport

