/*===-- llvm-c/Analysis.h - Analysis Library C Interface --------*- C++ -*-===*\
|*                                                                            *|
|*                     The LLVM Compiler Infrastructure                       *|
|*                                                                            *|
|* This file is distributed under the University of Illinois Open Source      *|
|* License. See LICENSE.TXT for details.                                      *|
|*                                                                            *|
|*===----------------------------------------------------------------------===*|
|*                                                                            *|
|* This header declares the C interface to libLLVMAnalysis.a, which           *|
|* implements various analyses of the LLVM IR.                                *|
|*                                                                            *|
|* Many exotic languages can interoperate with C code but have a harder time  *|
|* with C++ due to name mangling. So in addition to C, this interface enables *|
|* tools written in such languages.                                           *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/
module llvm.c.Analysis;

import llvm.c.Core;

extern(C):

enum LLVMVerifierFailureAction {
  AbortProcess, /* verifier will print to stderr and abort() */
  PrintMessage, /* verifier will print to stderr and return 1 */
  ReturnStatus  /* verifier will just return 1 */
}

/* Verifies that a module is valid, taking the specified action if not.
   Optionally returns a human-readable description of any invalid constructs.
   OutMessage must be disposed with LLVMDisposeMessage. */
LLVMBool LLVMVerifyModule(LLVMModuleRef M, LLVMVerifierFailureAction Action,
                          char **OutMessage);

/* Verifies that a single function is valid, taking the specified action. Useful
   for debugging. */
LLVMBool LLVMVerifyFunction(LLVMValueRef Fn, LLVMVerifierFailureAction Action);

/* Open up a ghostview window that displays the CFG of the current function.
   Useful for debugging. */
void LLVMViewFunctionCFG(LLVMValueRef Fn);
void LLVMViewFunctionCFGOnly(LLVMValueRef Fn);
