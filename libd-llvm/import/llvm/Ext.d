module llvm.Ext;

import llvm.c.Core;
import llvm.c.Target;

extern(C):

void LLVMSetStoreAlign(LLVMValueRef store, uint alignment);
uint LLVMGetStoreAlign(LLVMValueRef store);

void LLVMSetLoadAlign(LLVMValueRef store, uint alignment);
uint LLVMGetLoadAlign(LLVMValueRef store);

void LLVMSetAllocaAlign(LLVMValueRef alloc, uint alignment);
uint LLVMGetAllocaAlign(LLVMValueRef alloc);
int LLVMIsAllocaInst(LLVMValueRef V);

int LLVMIsTerminator(LLVMValueRef inst);

void LLVMDumpType(LLVMTypeRef type);

void LLVMEraseInstructionFromParent(LLVMValueRef V);

LLVMTypeRef LLVMGetStructElementType(LLVMTypeRef ST, uint elem_index);

LLVMValueRef LLVMConstRealFromBits(LLVMTypeRef T, uint bits, ulong* data, uint nbitwords);

void LLVMMoveBasicBlockAfter(LLVMBasicBlockRef src, LLVMBasicBlockRef tgt);

LLVMValueRef LLVMGetNamedAlias(LLVMModuleRef M, /*const*/ char *Name);

void LLVMAddRetAttr(LLVMValueRef Fn, LLVMAttribute PA);

// target triple binding

// returns the running host triple
char* LLVMGetHostTriple();

version(none) // disable for now, since this enum is too unstable in llvm
{
struct LLVM_OpaqueTriple {}
alias LLVM_OpaqueTriple* LLVMTripleRef;

enum LLVMArchType {
    UnknownArch,

    alpha,   // Alpha: alpha
    arm,     // ARM; arm, armv.*, xscale
    bfin,    // Blackfin: bfin
    cellspu, // CellSPU: spu, cellspu
    mips,    // MIPS: mips, mipsallegrex
    mipsel,  // MIPSEL: mipsel, mipsallegrexel, psp
    msp430,  // MSP430: msp430
    pic16,   // PIC16: pic16
    ppc,     // PPC: powerpc
    ppc64,   // PPC64: powerpc64
    sparc,   // Sparc: sparc
    systemz, // SystemZ: s390x
    tce,     // TCE (http://tce.cs.tut.fi/): tce
    thumb,   // Thumb: thumb, thumbv.*
    x86,     // X86: i[3-9]86
    x86_64,  // X86-64: amd64, x86_64
    xcore,   // XCore: xcore

    InvalidArch
};

enum LLVMVendorType {
    UnknownVendor,

    Apple,
    PC
};

enum LLVMOSType {
    UnknownOS,

    AuroraUX,
    Cygwin,
    Darwin,
    DragonFly,
    FreeBSD,
    Linux,
    MinGW32,
    MinGW64,
    NetBSD,
    OpenBSD,
    Solaris,
    Win32
};

LLVMTripleRef LLVMCreateTriple(char* str);
void LLVMDisposeTriple(LLVMTripleRef triple);

LLVMArchType LLVMTripleGetArch(LLVMTripleRef triple);
LLVMVendorType LLVMTripleGetVendor(LLVMTripleRef triple);
LLVMOSType LLVMTripleGetOS(LLVMTripleRef triple);
}

// TargetMachine binding

struct LLVM_OpaqueTargetMachine {}
alias LLVM_OpaqueTargetMachine* LLVMTargetMachineRef;

LLVMTargetMachineRef LLVMCreateTargetMachine(char* cpu, char* triple, char** feats, size_t nfeats);
void LLVMDisposeTargetMachine(LLVMTargetMachineRef machine);
LLVMTargetDataRef LLVMTargetMachineData(LLVMTargetMachineRef TM);

// Targets

void LLVMInitializeX86TargetInfo();
void LLVMInitializeX86Target();
void LLVMInitializeX86AsmPrinter();

void LLVMInitializePPCTargetInfo();
void LLVMInitializePPCTarget();
void LLVMInitializePPCAsmPrinter();

void LLVMInitializeARMTargetInfo();
void LLVMInitializeARMTarget();
void LLVMInitializeARMAsmPrinter();

void LLVMInitializeSparcTargetInfo();
void LLVMInitializeSparcTarget();
void LLVMInitializeSparcAsmPrinter();

// TODO add the rest

// Extra output functions
int LLVMWriteAsmToFile(LLVMModuleRef M, char* path, char** errstr);
int LLVMWriteNativeAsmToFile(LLVMTargetMachineRef TM, LLVMModuleRef M, char* path, int opt);

// More IPO

void LLVMAddInternalizePass(LLVMPassManagerRef PM, char** exp, uint nexps);
void LLVMAddTailDuplicationPass(LLVMPassManagerRef PM);
void LLVMAddIPSCCPPass(LLVMPassManagerRef PM);

// system utils

void LLVMPrintStackTraceOnErrorSignal();
