/*===-- llvm-c/Target.h - Target Lib C Iface --------------------*- C++ -*-===*/
/*                                                                            */
/*                     The LLVM Compiler Infrastructure                       */
/*                                                                            */
/* This file is distributed under the University of Illinois Open Source      */
/* License. See LICENSE.TXT for details.                                      */
/*                                                                            */
/*===----------------------------------------------------------------------===*/
/*                                                                            */
/* This header declares the C interface to libLLVMTarget.a, which             */
/* implements target information.                                             */
/*                                                                            */
/* Many exotic languages can interoperate with C code but have a harder time  */
/* with C++ due to name mangling. So in addition to C, this interface enables */
/* tools written in such languages.                                           */
/*                                                                            */
/*===----------------------------------------------------------------------===*/

module llvm.c.target;

import llvm.c.core;

extern(C) nothrow:

/**
 * @defgroup LLVMCTarget Target information
 * @ingroup LLVMC
 *
 * @{
 */

enum LLVMByteOrdering { BigEndian, LittleEndian };

struct __LLVMOpaqueTargetData {};
alias __LLVMOpaqueTargetData *LLVMTargetDataRef;
struct __LLVMOpaqueTargetLibraryInfotData {};
alias __LLVMOpaqueTargetLibraryInfotData *LLVMTargetLibraryInfoRef;
struct __LLVMStructLayout {};
alias __LLVMStructLayout *LLVMStructLayoutRef;

extern(D) string LLVM_TARGET(string delegate(string) nothrow fun)
{
  string ret;
  foreach (str; [
                  "ARM",
                  "CellSPU",
                  "CppBackend",
                  "Hexagon",
                  "Mips",
                  "MBlaze",
                  "MSP430",
                  "PowerPC",
                  "PTX",
                  "Sparc",
                  "X86",
                  "XCore",
                ])
  {
    ret ~= fun(str) ~ "\n";
  }
  return ret;
}

/* Declare all of the target-initialization functions that are available. */
extern(D) mixin(LLVM_TARGET(delegate string(string name) {
  return "extern(C) void LLVMInitialize" ~ name ~ "TargetInfo();";
}));

extern(D) mixin(LLVM_TARGET(delegate string(string name) {
  return "extern(C) void LLVMInitialize" ~ name ~ "Target();";
}));

extern(D) mixin(LLVM_TARGET(delegate string(string name) {
  return "extern(C) void LLVMInitialize" ~ name ~ "TargetMC();";
}));


extern(D) string LLVM_ASM_PRINTER(string delegate(string) nothrow fun)
{
  string ret;
  foreach (str; [
                  "ARM",
                  "CellSPU",
                  "Hexagon",
                  "Mips",
                  "MBlaze",
                  "MSP430",
                  "PowerPC",
                  "PTX",
                  "Sparc",
                  "X86",
                  "XCore",
                ])
  {
    ret ~= fun(str) ~ "\n";
  }
  return ret;
}

/* Declare all of the available assembly printer initialization functions. */
extern(D) mixin(LLVM_ASM_PRINTER(delegate string(string name) {
  return "extern(C) void LLVMInitialize" ~ name ~ "AsmPrinter();";
}));

extern(D) string LLVM_ASM_PARSER(string delegate(string) nothrow fun)
{
  string ret;
  foreach (str; [
                  "ARM",
                  "Mips",
                  "MBlaze",
                  "X86",
                ])
  {
    ret ~= fun(str) ~ "\n";
  }
  return ret;
}

/* Declare all of the available assembly parser initialization functions. */
extern(D) mixin(LLVM_ASM_PARSER(delegate string(string name) {
  return "extern(C) void LLVMInitialize" ~ name ~ "AsmParser();";
}));

extern(D) string LLVM_ASM_DISASSEMBLER(string delegate(string) nothrow fun)
{
  string ret;
  foreach (str; [
                  "ARM",
                  "Mips",
                  "MBlaze",
                  "X86",
                ])
  {
    ret ~= fun(str) ~ "\n";
  }
  return ret;
}

/* Declare all of the available disassembler initialization functions. */
extern(D) mixin(LLVM_ASM_PARSER(delegate string(string name) {
  return "extern(C) void LLVMInitialize" ~ name ~ "Disassembler();";
}));

/** LLVMInitializeAllTargetInfos - The main program should call this function if
    it wants access to all available targets that LLVM is configured to
    support. */
static void LLVMInitializeAllTargetInfos() {
  mixin(LLVM_TARGET(delegate string(string name) {
    return "LLVMInitialize" ~ name ~ "TargetInfo();";
  }));
}

/** LLVMInitializeAllTargets - The main program should call this function if it
    wants to link in all available targets that LLVM is configured to
    support. */
static void LLVMInitializeAllTargets() {
  mixin(LLVM_TARGET(delegate string(string name) {
    return "LLVMInitialize" ~ name ~ "Target();";
  }));
}

/** LLVMInitializeAllTargetMCs - The main program should call this function if
    it wants access to all available target MC that LLVM is configured to
    support. */
static void LLVMInitializeAllTargetMCs() {
  mixin(LLVM_TARGET(delegate string(string name) {
    return "LLVMInitialize" ~ name ~ "TargetMC();";
  }));
}
  
/** LLVMInitializeAllAsmPrinters - The main program should call this function if
    it wants all asm printers that LLVM is configured to support, to make them
    available via the TargetRegistry. */
static void LLVMInitializeAllAsmPrinters() {
  mixin(LLVM_ASM_PRINTER(delegate string(string name) {
    return "LLVMInitialize" ~ name ~ "AsmPrinter();";
  }));
}
  
/** LLVMInitializeAllAsmParsers - The main program should call this function if
    it wants all asm parsers that LLVM is configured to support, to make them
    available via the TargetRegistry. */
static void LLVMInitializeAllAsmParsers() {
  mixin(LLVM_ASM_PARSER(delegate string(string name) {
    return "LLVMInitialize" ~ name ~ "AsmParser();";
  }));
}
  
/** LLVMInitializeAllDisassemblers - The main program should call this function
    if it wants all disassemblers that LLVM is configured to support, to make
    them available via the TargetRegistry. */
static void LLVMInitializeAllDisassemblers() {
  mixin(LLVM_ASM_DISASSEMBLER(delegate string(string name) {
    return "LLVMInitialize" ~ name ~ "Disassembler();";
  }));
}
  
/** LLVMInitializeNativeTarget - The main program should call this function to
    initialize the native target corresponding to the host.  This is useful 
    for JIT applications to ensure that the target gets linked in correctly. */
static LLVMBool LLVMInitializeNativeTarget() {
  /* If we have a native target, initialize it to ensure it is linked in. */
  return 1;
}  

/*===-- Target Data -------------------------------------------------------===*/

/** Creates target data from a target layout string.
    See the constructor llvm::TargetData::TargetData. */
LLVMTargetDataRef LLVMCreateTargetData(const(char) *StringRep);

/** Adds target data information to a pass manager. This does not take ownership
    of the target data.
    See the method llvm::PassManagerBase::add. */
void LLVMAddTargetData(LLVMTargetDataRef, LLVMPassManagerRef);

/** Adds target library information to a pass manager. This does not take
    ownership of the target library info.
    See the method llvm::PassManagerBase::add. */
void LLVMAddTargetLibraryInfo(LLVMTargetLibraryInfoRef, LLVMPassManagerRef);

/** Converts target data to a target layout string. The string must be disposed
    with LLVMDisposeMessage.
    See the constructor llvm::TargetData::TargetData. */
char *LLVMCopyStringRepOfTargetData(LLVMTargetDataRef);

/** Returns the byte order of a target, either LLVMBigEndian or
    LLVMLittleEndian.
    See the method llvm::TargetData::isLittleEndian. */
LLVMByteOrdering LLVMByteOrder(LLVMTargetDataRef);

/** Returns the pointer size in bytes for a target.
    See the method llvm::TargetData::getPointerSize. */
uint LLVMPointerSize(LLVMTargetDataRef);

/** Returns the integer type that is the same size as a pointer on a target.
    See the method llvm::TargetData::getIntPtrType. */
LLVMTypeRef LLVMIntPtrType(LLVMTargetDataRef);

/** Computes the size of a type in bytes for a target.
    See the method llvm::TargetData::getTypeSizeInBits. */
ulong LLVMSizeOfTypeInBits(LLVMTargetDataRef, LLVMTypeRef);

/** Computes the storage size of a type in bytes for a target.
    See the method llvm::TargetData::getTypeStoreSize. */
ulong LLVMStoreSizeOfType(LLVMTargetDataRef, LLVMTypeRef);

/** Computes the ABI size of a type in bytes for a target.
    See the method llvm::TargetData::getTypeAllocSize. */
ulong LLVMABISizeOfType(LLVMTargetDataRef, LLVMTypeRef);

/** Computes the ABI alignment of a type in bytes for a target.
    See the method llvm::TargetData::getTypeABISize. */
uint LLVMABIAlignmentOfType(LLVMTargetDataRef, LLVMTypeRef);

/** Computes the call frame alignment of a type in bytes for a target.
    See the method llvm::TargetData::getTypeABISize. */
uint LLVMCallFrameAlignmentOfType(LLVMTargetDataRef, LLVMTypeRef);

/** Computes the preferred alignment of a type in bytes for a target.
    See the method llvm::TargetData::getTypeABISize. */
uint LLVMPreferredAlignmentOfType(LLVMTargetDataRef, LLVMTypeRef);

/** Computes the preferred alignment of a global variable in bytes for a target.
    See the method llvm::TargetData::getPreferredAlignment. */
uint LLVMPreferredAlignmentOfGlobal(LLVMTargetDataRef,
                                        LLVMValueRef GlobalVar);

/** Computes the structure element that contains the byte offset for a target.
    See the method llvm::StructLayout::getElementContainingOffset. */
uint LLVMElementAtOffset(LLVMTargetDataRef, LLVMTypeRef StructTy,
                             ulong Offset);

/** Computes the byte offset of the indexed struct element for a target.
    See the method llvm::StructLayout::getElementContainingOffset. */
ulong LLVMOffsetOfElement(LLVMTargetDataRef, LLVMTypeRef StructTy,
                                       uint Element);

/** Deallocates a TargetData.
    See the destructor llvm::TargetData::~TargetData. */
void LLVMDisposeTargetData(LLVMTargetDataRef);

/**
 * @}
 */
