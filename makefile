all:
	dmd -ofsdc src/sdc/*.d src/sdc/ast/*.d -w -debug -gc

