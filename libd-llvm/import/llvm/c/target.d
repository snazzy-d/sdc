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

public import llvm.c.types;

extern(C) nothrow:

/**
 * @defgroup LLVMCTarget Target information
 * @ingroup LLVMC
 *
 * @{
 */

enum LLVMByteOrdering { BigEndian, LittleEndian };

struct __LLVMOpaqueTargetData {};
alias LLVMTargetDataRef = __LLVMOpaqueTargetData*;
struct __LLVMOpaqueTargetLibraryInfotData {};
alias LLVMTargetLibraryInfoRef = __LLVMOpaqueTargetLibraryInfotData*;
struct __LLVMStructLayout {};

extern(D) string LLVM_TARGET(string delegate(string) nothrow fun) {
  string ret;
  foreach (str; [
  /*
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
  */
    "X86",
  /*
    "XCore",
  */
  ]) {
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


extern(D) string LLVM_ASM_PRINTER(string delegate(string) nothrow fun) {
  string ret;
  foreach (str; [
  /*
    "ARM",
    "CellSPU",
    "Hexagon",
    "Mips",
    "MBlaze",
    "MSP430",
    "PowerPC",
    "PTX",
    "Sparc",
  */
    "X86",
  /*
    "XCore",
  */
  ]) {
    ret ~= fun(str) ~ "\n";
  }

  return ret;
}

/* Declare all of the available assembly printer initialization functions. */
extern(D) mixin(LLVM_ASM_PRINTER(delegate string(string name) {
  return "extern(C) void LLVMInitialize" ~ name ~ "AsmPrinter();";
}));

extern(D) string LLVM_ASM_PARSER(string delegate(string) nothrow fun) {
  string ret;
  foreach (str; [
  /*
    "ARM",
    "Mips",
    "MBlaze",
  */
    "X86",
  ]) {
    ret ~= fun(str) ~ "\n";
  }

  return ret;
}

/* Declare all of the available assembly parser initialization functions. */
extern(D) mixin(LLVM_ASM_PARSER(delegate string(string name) {
  return "extern(C) void LLVMInitialize" ~ name ~ "AsmParser();";
}));

extern(D) string LLVM_ASM_DISASSEMBLER(string delegate(string) nothrow fun) {
  string ret;
  foreach (str; [
  /*
    "ARM",
    "Mips",
    "MBlaze",
  */
    "X86",
  ]) {
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
/+
/** LLVMInitializeNativeTargetAsmParser - The main program should call this
    function to initialize the parser for the native target corresponding to the
    host. */
static inline LLVMBool LLVMInitializeNativeAsmParser() {
#ifdef LLVM_NATIVE_ASMPARSER
  LLVM_NATIVE_ASMPARSER();
  return 0;
#else
  return 1;
#endif
}

/** LLVMInitializeNativeTargetAsmPrinter - The main program should call this
    function to initialize the printer for the native target corresponding to
    the host. */
static inline LLVMBool LLVMInitializeNativeAsmPrinter() {
#ifdef LLVM_NATIVE_ASMPRINTER
  LLVM_NATIVE_ASMPRINTER();
  return 0;
#else
  return 1;
#endif
}

/** LLVMInitializeNativeTargetDisassembler - The main program should call this
    function to initialize the disassembler for the native target corresponding
    to the host. */
static inline LLVMBool LLVMInitializeNativeDisassembler() {
#ifdef LLVM_NATIVE_DISASSEMBLER
  LLVM_NATIVE_DISASSEMBLER();
  return 0;
#else
  return 1;
#endif
}
+/
/*===-- Target Data -------------------------------------------------------===*/

/**
 * Obtain the data layout for a module.
 *
 * @see Module::getDataLayout()
 */
LLVMTargetDataRef LLVMGetModuleDataLayout(LLVMModuleRef M);

/**
 * Set the data layout for a module.
 *
 * @see Module::setDataLayout()
 */
void LLVMSetModuleDataLayout(LLVMModuleRef M, LLVMTargetDataRef DL);

/** Creates target data from a target layout string.
    See the constructor llvm::DataLayout::DataLayout. */
LLVMTargetDataRef LLVMCreateTargetData(const(char)* StringRep);

/** Deallocates a TargetData.
    See the destructor llvm::DataLayout::~DataLayout. */
void LLVMDisposeTargetData(LLVMTargetDataRef TD);

/** Adds target library information to a pass manager. This does not take
    ownership of the target library info.
    See the method llvm::PassManagerBase::add. */
void LLVMAddTargetLibraryInfo(LLVMTargetLibraryInfoRef TLI,
                              LLVMPassManagerRef PM);

/** Converts target data to a target layout string. The string must be disposed
    with LLVMDisposeMessage.
    See the constructor llvm::DataLayout::DataLayout. */
char* LLVMCopyStringRepOfTargetData(LLVMTargetDataRef TD);

/** Returns the byte order of a target, either LLVMBigEndian or
    LLVMLittleEndian.
    See the method llvm::DataLayout::isLittleEndian. */
LLVMByteOrdering LLVMByteOrder(LLVMTargetDataRef TD);

/** Returns the pointer size in bytes for a target.
    See the method llvm::TargetData::getPointerSize. */
uint LLVMPointerSize(LLVMTargetDataRef TD);

/** Returns the pointer size in bytes for a target for a specified
    address space.
    See the method llvm::DataLayout::getPointerSize. */
uint LLVMPointerSizeForAS(LLVMTargetDataRef TD, uint AS);

/** Returns the integer type that is the same size as a pointer on a target.
    See the method llvm::DataLayout::getIntPtrType. */
LLVMTypeRef LLVMIntPtrType(LLVMTargetDataRef TD);

/** Returns the integer type that is the same size as a pointer on a target.
    This version allows the address space to be specified.
    See the method llvm::DataLayout::getIntPtrType. */
LLVMTypeRef LLVMIntPtrTypeForAS(LLVMTargetDataRef TD, uint AS);

/** Returns the integer type that is the same size as a pointer on a target.
    See the method llvm::DataLayout::getIntPtrType. */
LLVMTypeRef LLVMIntPtrTypeInContext(LLVMContextRef C, LLVMTargetDataRef TD);

/** Returns the integer type that is the same size as a pointer on a target.
    This version allows the address space to be specified.
    See the method llvm::DataLayout::getIntPtrType. */
LLVMTypeRef LLVMIntPtrTypeForASInContext(LLVMContextRef C, LLVMTargetDataRef TD,
                                         uint AS);

/** Computes the size of a type in bytes for a target.
    See the method llvm::DataLayout::getTypeSizeInBits. */
ulong LLVMSizeOfTypeInBits(LLVMTargetDataRef TD, LLVMTypeRef Ty);

/** Computes the storage size of a type in bytes for a target.
    See the method llvm::DataLayout::getTypeStoreSize. */
ulong LLVMStoreSizeOfType(LLVMTargetDataRef TD, LLVMTypeRef Ty);

/** Computes the ABI size of a type in bytes for a target.
    See the method llvm::DataLayout::getTypeAllocSize. */
ulong LLVMABISizeOfType(LLVMTargetDataRef TD, LLVMTypeRef Ty);

/** Computes the ABI alignment of a type in bytes for a target.
    See the method llvm::DataLayout::getTypeABISize. */
uint LLVMABIAlignmentOfType(LLVMTargetDataRef TD, LLVMTypeRef Ty);

/** Computes the call frame alignment of a type in bytes for a target.
    See the method llvm::DataLayout::getTypeABISize. */
uint LLVMCallFrameAlignmentOfType(LLVMTargetDataRef TD, LLVMTypeRef Ty);

/** Computes the preferred alignment of a type in bytes for a target.
    See the method llvm::DataLayout::getTypeABISize. */
uint LLVMPreferredAlignmentOfType(LLVMTargetDataRef TD, LLVMTypeRef Ty);

/** Computes the preferred alignment of a global variable in bytes for a target.
    See the method llvm::DataLayout::getPreferredAlignment. */
uint LLVMPreferredAlignmentOfGlobal(LLVMTargetDataRef TD,
                                    LLVMValueRef GlobalVar);

/** Computes the structure element that contains the byte offset for a target.
    See the method llvm::StructLayout::getElementContainingOffset. */
uint LLVMElementAtOffset(LLVMTargetDataRef TD, LLVMTypeRef StructTy,
                         ulong Offset);

/** Computes the byte offset of the indexed struct element for a target.
    See the method llvm::StructLayout::getElementContainingOffset. */
ulong LLVMOffsetOfElement(LLVMTargetDataRef TD,
                          LLVMTypeRef StructTy, uint Element);

/**
 * @}
 */
