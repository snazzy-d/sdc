FLAGS="-m64 -w -debug -g -unittest -cov"
PROFILE_FLAGS="-profile -version=No_Race -profile=gc"
INCLUDE_PATHS="-Isdc/src -Ilibd-llvm/import -Ilibd-llvm/src -Ilibd/src"
SDC_SRC="sdc/src/sdc/*.d sdc/src/util/*.d"
LIBD_LLVM_SRC="libd-llvm/src/d/llvm/*.d" 
LIBD_SRC="libd/src/d/*/*.d libd/src/util/*.d libd/src/d/*.d"

dmd -c -ofobj/tester-cov.o $INCLUDE_PATHS $SDC_SRC $LIBD_LLVM_SRC $LIBD_SRC tester/src/tester.d tester/src/atomicarray.d $FLAGS $PROFILE_FLAGS
gcc -o bin/tester-cov obj/tester-cov.o -m64  -L. -lphobos2 `llvm-config --ldflags` `llvm-config --libs` `llvm-config --system-libs` -lstdc++ -export-dynamic
