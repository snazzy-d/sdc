#include "llvm-c/Core.h"
#include "llvm-c/Target.h"
#include "llvm/Module.h"
#include "llvm/CodeGen/MachineCodeEmitter.h"
#include "llvm/GlobalValue.h"
#include "llvm/PassManager.h"
#include "llvm/ADT/Triple.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/FormattedStream.h"
#include "llvm/MC/SubtargetFeature.h"
#include "llvm/Target/TargetData.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Support/TargetRegistry.h"
#include "llvm/Support/TargetSelect.h"

#include <cstdio>

using namespace llvm;

typedef struct LLVMOpaqueTargetMachine *LLVMTargetMachineRef;

namespace llvm
{
    class TargetMachine;

    inline TargetMachine *unwrap(LLVMTargetMachineRef P) {
        return reinterpret_cast<TargetMachine*>(P);
    }

    inline LLVMTargetMachineRef wrap(const TargetMachine *P) {
        return reinterpret_cast<LLVMTargetMachineRef>(const_cast<TargetMachine*>(P));
    }
}

extern "C" {

LLVMTargetMachineRef LLVMCreateTargetMachine(const char* cpu, const char* triple, const char** feats, size_t nfeats, int pic)
{
    // based on LDC code

    // find target from the given triple and cpu
    const Target* target = NULL;
    for (TargetRegistry::iterator it = TargetRegistry::begin(),
             ie = TargetRegistry::end(); it != ie; ++it)
    {
#if 0
        printf("cpu: %s target: %s\n", cpu, it->getName());
#endif
        if (strcmp(cpu, it->getName()) == 0)
        {
            target = &*it;
            break;
        }
    }
    assert(target != NULL);

    // add any features the user might have provided
    Twine twine;

    SubtargetFeatures features;
    //features.setCPU(cpu);

    for (size_t i = 0; i < nfeats; ++i)
    {
        features.AddFeature(feats[i]);
        twine = twine.concat(features.getString());
    }

    // create machine
    TargetMachine* targetMachine = target->createTargetMachine(triple, cpu, twine.str(), pic ? Reloc::PIC_ : Reloc::Default, CodeModel::Default);
    if (!targetMachine)
        return NULL;

    return wrap(targetMachine);
}

void LLVMDisposeTargetMachine(LLVMTargetMachineRef machine)
{
    delete unwrap(machine);
}

LLVMTargetDataRef LLVMTargetMachineData(LLVMTargetMachineRef TM)
{
    return wrap(unwrap(TM)->getTargetData());
}

// LLVM to native asm

// stolen from LDC and modified
// based on llc (from LLVM) code, University of Illinois Open Source License
int LLVMWriteNativeAsmToFile(LLVMTargetMachineRef TMRef, LLVMModuleRef MRef, const char* filename, int opt) //, int pic)
{
    TargetMachine* TM = unwrap(TMRef);
    Module* M = unwrap(MRef);

    //TargetMachine::setRelocationModel(pic ? Reloc::PIC_ : Reloc::Default);

#if 0
    printf("trying to write native asm for target: %s\n", TM->getTarget().getName());
#endif

    std::string Err;

    // Build up all of the passes that we want to do to the module.
    FunctionPassManager Passes(M);

    // Add TargetData
    if (const TargetData *TD = TM->getTargetData())
        Passes.add(new TargetData(*TD));
    else
        assert(0); // Passes.add(new TargetData(M));

    // debug info doesn't work properly with OptLevel != None!
    CodeGenOpt::Level OLvl = CodeGenOpt::Default;
    if (opt)
        OLvl = CodeGenOpt::Aggressive;
    else
        OLvl = CodeGenOpt::None;

    // open output file
    raw_fd_ostream out(filename, Err, raw_fd_ostream::F_Binary);
    assert(Err.empty());

    // add codegen passes
    formatted_raw_ostream fout(out);
    bool error = TM->addPassesToEmitFile(Passes, fout, TargetMachine::CGFT_AssemblyFile, OLvl);
    assert(error == false); // Target does not support generation of this file type!

    Passes.doInitialization();

    // Run our queue of passes all at once now, efficiently.
    for (llvm::Module::iterator I = M->begin(), E = M->end(); I != E; ++I)
        if (!I->isDeclaration())
            Passes.run(*I);

    Passes.doFinalization();

    fout.flush();
    
    return 1;
}

// write llvm asm to file instead of stdout
int LLVMWriteAsmToFile(LLVMModuleRef M, const char* path, const char** errstr)
{
    std::string errs;
    raw_fd_ostream out(path, errs, raw_fd_ostream::F_Binary);
    if (!errs.empty())
    {
        if (errstr)
            *errstr = strdup(errs.c_str());
        return 0;
    }
    unwrap(M)->print(out, NULL);
    return 1;
}

}
