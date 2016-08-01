// RUN: %sdc %s -S --emit-llvm -o - | FileCheck %s --check-prefix LLVM
// RUN: %sdc %s -c --emit-llvm -o - | FileCheck %s --check-prefix BITCODE
// RUN: %sdc %s -S             -o - | FileCheck %s --check-prefix ASM

// BITCODE: BC

int main() {
    return 42;
// Try to keep these very simple checks independent of architecture:
// LLVM:  ret i32 42 
// ASM:  $42
// ASM:  ret
}
