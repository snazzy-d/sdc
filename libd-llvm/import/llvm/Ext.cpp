#include "llvm/ADT/Triple.h"
#include "llvm/LLVMContext.h"
#include "llvm/Support/Host.h"
#include "llvm/Support/Signals.h"
#include "llvm/PassManager.h"
#include "llvm/Transforms/IPO.h"
#include "llvm/Transforms/Scalar.h"

#include "llvm-c/Core.h"
#include "llvm-c/Target.h"
#include "llvm-c/Transforms/IPO.h"

// extensions to the LLVM C interface, we'll be needing more eventually ...

using namespace llvm;

extern "C" {

LLVMTypeRef LLVMMetadataType()
{
  return wrap(Type::getMetadataTy(*unwrap(LLVMGetGlobalContext())));
}
LLVMValueRef LLVMMetadataOperand(LLVMValueRef md, unsigned i)
{
	return wrap(unwrap<MDNode>(md)->getOperand(i));
}

// load/store alignment

void LLVMSetLoadAlign(LLVMValueRef store, unsigned align)
{
    cast<LoadInst>(unwrap(store))->setAlignment(align);
}
unsigned LLVMGetLoadAlign(LLVMValueRef store)
{
    return cast<LoadInst>(unwrap(store))->getAlignment();
}

void LLVMSetStoreAlign(LLVMValueRef store, unsigned align)
{
    cast<StoreInst>(unwrap(store))->setAlignment(align);
}
unsigned LLVMGetStoreAlign(LLVMValueRef store)
{
    return cast<StoreInst>(unwrap(store))->getAlignment();
}

void LLVMSetAllocaAlign(LLVMValueRef alloc, unsigned align)
{
    cast<AllocaInst>(unwrap(alloc))->setAlignment(align);
}
unsigned LLVMGetAllocaAlign(LLVMValueRef alloc)
{
    return cast<AllocaInst>(unwrap(alloc))->getAlignment();
}
int LLVMIsAllocaInst(LLVMValueRef V)
{
    return isa<AllocaInst>(unwrap(V)) ? 1 : 0;
}

// is terminator
int LLVMIsTerminator(LLVMValueRef inst)
{
    if (dyn_cast<TerminatorInst>(unwrap(inst)) != NULL)
        return 1;
    return 0;
}

// dump type
void LLVMDumpType(LLVMTypeRef type)
{
    unwrap(type)->dump();
}

// erase instruction
void LLVMEraseInstructionFromParent(LLVMValueRef V)
{
    cast<Instruction>(unwrap(V))->eraseFromParent();
}

LLVMTypeRef LLVMGetStructElementType(LLVMTypeRef ST, unsigned elem_index)
{
    return wrap(
        cast<StructType>(unwrap(ST))->getElementType(elem_index)
    );
}

// llvm/ADT/Triple.h binding

// disabled for now

#if 0

typedef Triple* LLVMTripleRef;

LLVMTripleRef LLVMCreateTriple(const char* str)
{
    return new Triple(str);
}

void LLVMDisposeTriple(LLVMTripleRef triple)
{
    delete triple;
}

Triple::ArchType LLVMTripleGetArch(LLVMTripleRef triple)
{
    return triple->getArch();
}

Triple::VendorType LLVMTripleGetVendor(LLVMTripleRef triple)
{
    return triple->getVendor();
}

Triple::OSType LLVMTripleGetOS(LLVMTripleRef triple)
{
    return triple->getOS();
}

#endif

const char* LLVMGetHostTriple()
{
    static std::string str; // OK ?
    if (str.empty())
        str = sys::getHostTriple();
    return str.c_str();
}

// internalize

//ModulePass *createInternalizePass(const std::vector<const char *> &exportList);

void LLVMAddInternalizePassWithExportList(LLVMPassManagerRef PM, const char* exp[], unsigned nexps) {
  std::vector<const char *> exportList(nexps, NULL);
  for (unsigned i = 0; i < nexps; ++i)
    exportList[i] = exp[i];
  unwrap(PM)->add(createInternalizePass(exportList));
}

// other optimizations

void LLVMAddCorrelatedValuePropagationPass(LLVMPassManagerRef PM)
{
	unwrap(PM)->add(createCorrelatedValuePropagationPass());
}

void LLVMAddTailDuplicationPass(LLVMPassManagerRef PM)
{
    unwrap(PM)->add(createTailDuplicationPass());
}

// system stuff

void LLVMPrintStackTraceOnErrorSignal()
{
    sys::PrintStackTraceOnErrorSignal();
}

// const long double

LLVMValueRef LLVMConstRealFromBits(LLVMTypeRef T, unsigned bits, uint64_t* data, unsigned nbitwords)
{
    return wrap(ConstantFP::get(getGlobalContext(), APFloat(APInt(bits, nbitwords, data))));
}

// get alias

LLVMValueRef LLVMGetNamedAlias(LLVMModuleRef M, const char *Name)
{
    return wrap(unwrap(M)->getNamedAlias(Name));
}

// add attribute to return value

void LLVMAddRetAttr(LLVMValueRef Fn, LLVMAttribute PA) {
  Function *Func = unwrap<Function>(Fn);
  const AttrListPtr PAL = Func->getAttributes();
  const AttrListPtr PALnew = PAL.addAttr(0, PA);
  Func->setAttributes(PALnew);
}

}
