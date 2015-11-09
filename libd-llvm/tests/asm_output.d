// RUN: %sdc %s -S --emit-llvm -o %t.ll  &&  FileCheck %s --check-prefix LLVM < %t.ll
// RUN: %sdc %s -c --emit-llvm -o %t.bc  &&  FileCheck %s --check-prefix BITCODE < %t.bc
// RUN: %sdc %s -S             -o %t.s   &&  FileCheck %s --check-prefix ASM < %t.s

// BITCODE: BC

int main() {
    return 42;
// Try to keep these very simple checks independent of architecture:
// LLVM:  ret i32 42 
// ASM:  $42
// ASM:  ret
}
