/*===-- llvm-c/Object.h - Object Lib C Iface --------------------*- C++ -*-===*/
/*                                                                            */
/*                     The LLVM Compiler Infrastructure                       */
/*                                                                            */
/* This file is distributed under the University of Illinois Open Source      */
/* License. See LICENSE.TXT for details.                                      */
/*                                                                            */
/*===----------------------------------------------------------------------===*/
/*                                                                            */
/* This header declares the C interface to libLLVMObject.a, which             */
/* implements object file reading and writing.                                */
/*                                                                            */
/* Many exotic languages can interoperate with C code but have a harder time  */
/* with C++ due to name mangling. So in addition to C, this interface enables */
/* tools written in such languages.                                           */
/*                                                                            */
/*===----------------------------------------------------------------------===*/
module llvm.c.Object;

import llvm.c.Core;

extern(C):

struct __LLVMOpaqueObjectFile {}
alias __LLVMOpaqueObjectFile* LLVMObjectFileRef;

struct __LLVMOpaqueSectionIterator {}
alias __LLVMOpaqueSectionIterator* LLVMSectionIteratorRef;

LLVMObjectFileRef LLVMCreateObjectFile(LLVMMemoryBufferRef MemBuf);
void LLVMDisposeObjectFile(LLVMObjectFileRef ObjectFile);

LLVMSectionIteratorRef LLVMGetSections(LLVMObjectFileRef ObjectFile);
void LLVMDisposeSectionIterator(LLVMSectionIteratorRef SI);
LLVMBool LLVMIsSectionIteratorAtEnd(LLVMObjectFileRef ObjectFile,
                                LLVMSectionIteratorRef SI);
void LLVMMoveToNextSection(LLVMSectionIteratorRef SI);
/*const*/ char* LLVMGetSectionName(LLVMSectionIteratorRef SI);
ulong LLVMGetSectionSize(LLVMSectionIteratorRef SI);
/*const*/ char* LLVMGetSectionContents(LLVMSectionIteratorRef SI);
