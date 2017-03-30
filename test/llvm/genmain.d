// RUN: %sdc %s -S --emit-llvm -o - | FileCheck %s --check-prefix RAW
// RUN: %sdc %s --main -S --emit-llvm -o - | FileCheck %s --check-prefix MAIN

// RAW-NOT: define i32 @_Dmain()
// MAIN: define i32 @_Dmain()

int main() {
// RAW: define i32 @_D7genmain4mainFMZi
// RAW: ret i32 42
// MAIN: define i32 @_D7genmain4mainFMZi
// MAIN: ret i32 42
	return 42;
}

// RAW-NOT: define i32 @_Dmain()
// MAIN-NOT: define i32 @_Dmain()
