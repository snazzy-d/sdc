/*===-- llvm-c/Transform/PassManagerBuilder.h - PMB C Interface ---*- C -*-===*\
|*                                                                            *|
|*                     The LLVM Compiler Infrastructure                       *|
|*                                                                            *|
|* This file is distributed under the University of Illinois Open Source      *|
|* License. See LICENSE.TXT for details.                                      *|
|*                                                                            *|
|*===----------------------------------------------------------------------===*|
|*                                                                            *|
|* This header declares the C interface to the PassManagerBuilder class.      *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/
module llvm.c.transforms.PassManagerBuilder;

import llvm.c.Core;

extern(C):

struct __LLVMOpaquePassManagerBuilder {}
alias __LLVMOpaquePassManagerBuilder* LLVMPassManagerBuilderRef;


/** See llvm::PassManagerBuilder. */
LLVMPassManagerBuilderRef LLVMPassManagerBuilderCreate();
void LLVMPassManagerBuilderDispose(LLVMPassManagerBuilderRef PMB);

/** See llvm::PassManagerBuilder::OptLevel. */
void
LLVMPassManagerBuilderSetOptLevel(LLVMPassManagerBuilderRef PMB,
                                  uint OptLevel);

/** See llvm::PassManagerBuilder::SizeLevel. */
void
LLVMPassManagerBuilderSetSizeLevel(LLVMPassManagerBuilderRef PMB,
                                   uint SizeLevel);

/** See llvm::PassManagerBuilder::DisableUnitAtATime. */
void
LLVMPassManagerBuilderSetDisableUnitAtATime(LLVMPassManagerBuilderRef PMB,
                                            LLVMBool Value);

/** See llvm::PassManagerBuilder::DisableUnrollLoops. */
void
LLVMPassManagerBuilderSetDisableUnrollLoops(LLVMPassManagerBuilderRef PMB,
                                            LLVMBool Value);

/** See llvm::PassManagerBuilder::DisableSimplifyLibCalls */
void
LLVMPassManagerBuilderSetDisableSimplifyLibCalls(LLVMPassManagerBuilderRef PMB,
                                                 LLVMBool Value);

/** See llvm::PassManagerBuilder::Inliner. */
void
LLVMPassManagerBuilderUseInlinerWithThreshold(LLVMPassManagerBuilderRef PMB,
                                              uint Threshold);

/** See llvm::PassManagerBuilder::populateFunctionPassManager. */
void
LLVMPassManagerBuilderPopulateFunctionPassManager(LLVMPassManagerBuilderRef PMB,
                                                  LLVMPassManagerRef PM);

/** See llvm::PassManagerBuilder::populateModulePassManager. */
void
LLVMPassManagerBuilderPopulateModulePassManager(LLVMPassManagerBuilderRef PMB,
                                                LLVMPassManagerRef PM);

/** See llvm::PassManagerBuilder::populateLTOPassManager. */
void LLVMPassManagerBuilderPopulateLTOPassManager(LLVMPassManagerBuilderRef PMB,
                                                  LLVMPassManagerRef PM,
                                                  bool Internalize,
                                                  bool RunInliner);
