/*===---------------------------Vectorize.h --------------------- -*- C -*-===*\
|*===----------- Vectorization Transformation Library C Interface ---------===*|
|*                                                                            *|
|*                     The LLVM Compiler Infrastructure                       *|
|*                                                                            *|
|* This file is distributed under the University of Illinois Open Source      *|
|* License. See LICENSE.TXT for details.                                      *|
|*                                                                            *|
|*===----------------------------------------------------------------------===*|
|*                                                                            *|
|* This header declares the C interface to libLLVMVectorize.a, which          *|
|* implements various vectorization transformations of the LLVM IR.           *|
|*                                                                            *|
|* Many exotic languages can interoperate with C code but have a harder time  *|
|* with C++ due to name mangling. So in addition to C, this interface enables *|
|* tools written in such languages.                                           *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

module llvm.c.transforms.vectorize;

import llvm.c.core;

extern(C) nothrow:

/**
 * @defgroup LLVMCTransformsVectorize Vectorization transformations
 * @ingroup LLVMCTransforms
 *
 * @{
 */

/** See llvm::createBBVectorizePass function. */
void LLVMAddBBVectorizePass(LLVMPassManagerRef PM);

/** See llvm::createLoopVectorizePass function. */
void LLVMAddLoopVectorizePass(LLVMPassManagerRef PM);

/** See llvm::createSLPVectorizerPass function. */
void LLVMAddSLPVectorizePass(LLVMPassManagerRef PM);

/**
 * @}
 */
