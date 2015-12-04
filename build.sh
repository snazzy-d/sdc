FLAGS="-m64 -w -debug -g -unittest"
PROFILE_FLAGS="-profile -version=No_Race"
INCLUDE_PATHS="-Isdc/src -Ilibd-llvm/import -Ilibd-llvm/src -Ilibd/src"
SDC_SRC="sdc/src/sdc/*.d sdc/src/util/*.d"
LIBD_LLVM_SRC="libd-llvm/src/d/llvm/*.d" 
LIBD_SRC="libd/src/d/*/*.d libd/src/util/*.d libd/src/d/*.d"

#dmd -lib $INCLUDE_PATHS $SDC_SRC $LIBD_LLVM_SRC $LIBD_SRC -version=SDC_Library -oflibsdc.a $FLAGS
#dmd -c $INCLUDE_PATHS sdc/src/sdc/main.d $FLAGS -ofsdc.o
dmd -c $INCLUDE_PATHS $SDC_SRC $LIBD_LLVM_SRC $LIBD_SRC tester/src/tester.d tester/src/atomicarray.d $FLAGS -version=SDC_Library -oftester.o
#gcc -o bin/sdc sdc.o -m64  -L. -lsdc -lphobos2 `llvm-config --ldflags` `llvm-config --libs` `llvm-config --system-libs` -lstdc++ -export-dynamic
gcc -o bin/tester tester.o -m64  -L. -lphobos2 `llvm-config --ldflags` `llvm-config --libs` `llvm-config --system-libs` -lstdc++ -export-dynamic

bin/tester
