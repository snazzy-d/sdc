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

module llvm.c.object;

import core.stdc.stdint : uint64_t;
import llvm.c.core;

extern(C) nothrow:

/**
 * @defgroup LLVMCObject Object file reading and writing
 * @ingroup LLVMC
 *
 * @{
 */

// Opaque type wrappers
struct __LLVMOpaqueObjectFile {};
alias __LLVMOpaqueObjectFile *LLVMObjectFileRef;
struct __LLVMOpaqueSectionIterator {};
alias __LLVMOpaqueSectionIterator *LLVMSectionIteratorRef;
struct __LLVMOpaqueSymbolIterator {};
alias __LLVMOpaqueSymbolIterator *LLVMSymbolIteratorRef;
struct __LLVMOpaqueRelocationIterator {};
alias __LLVMOpaqueRelocationIterator *LLVMRelocationIteratorRef;

// ObjectFile creation
LLVMObjectFileRef LLVMCreateObjectFile(LLVMMemoryBufferRef MemBuf);
void LLVMDisposeObjectFile(LLVMObjectFileRef ObjectFile);

// ObjectFile Section iterators
LLVMSectionIteratorRef LLVMGetSections(LLVMObjectFileRef ObjectFile);
void LLVMDisposeSectionIterator(LLVMSectionIteratorRef SI);
LLVMBool LLVMIsSectionIteratorAtEnd(LLVMObjectFileRef ObjectFile,
                                LLVMSectionIteratorRef SI);
void LLVMMoveToNextSection(LLVMSectionIteratorRef SI);
void LLVMMoveToContainingSection(LLVMSectionIteratorRef Sect,
                                 LLVMSymbolIteratorRef Sym);

// ObjectFile Symbol iterators
LLVMSymbolIteratorRef LLVMGetSymbols(LLVMObjectFileRef ObjectFile);
void LLVMDisposeSymbolIterator(LLVMSymbolIteratorRef SI);
LLVMBool LLVMIsSymbolIteratorAtEnd(LLVMObjectFileRef ObjectFile,
                                LLVMSymbolIteratorRef SI);
void LLVMMoveToNextSymbol(LLVMSymbolIteratorRef SI);

// SectionRef accessors
const(char) *LLVMGetSectionName(LLVMSectionIteratorRef SI);
uint64_t LLVMGetSectionSize(LLVMSectionIteratorRef SI);
const(char) *LLVMGetSectionContents(LLVMSectionIteratorRef SI);
uint64_t LLVMGetSectionAddress(LLVMSectionIteratorRef SI);
LLVMBool LLVMGetSectionContainsSymbol(LLVMSectionIteratorRef SI,
                                 LLVMSymbolIteratorRef Sym);

// Section Relocation iterators
LLVMRelocationIteratorRef LLVMGetRelocations(LLVMSectionIteratorRef Section);
void LLVMDisposeRelocationIterator(LLVMRelocationIteratorRef RI);
LLVMBool LLVMIsRelocationIteratorAtEnd(LLVMSectionIteratorRef Section,
                                       LLVMRelocationIteratorRef RI);
void LLVMMoveToNextRelocation(LLVMRelocationIteratorRef RI);


// SymbolRef accessors
const(char) *LLVMGetSymbolName(LLVMSymbolIteratorRef SI);
uint64_t LLVMGetSymbolAddress(LLVMSymbolIteratorRef SI);
uint64_t LLVMGetSymbolFileOffset(LLVMSymbolIteratorRef SI);
uint64_t LLVMGetSymbolSize(LLVMSymbolIteratorRef SI);

// RelocationRef accessors
uint64_t LLVMGetRelocationAddress(LLVMRelocationIteratorRef RI);
uint64_t LLVMGetRelocationOffset(LLVMRelocationIteratorRef RI);
LLVMSymbolIteratorRef LLVMGetRelocationSymbol(LLVMRelocationIteratorRef RI);
uint64_t LLVMGetRelocationType(LLVMRelocationIteratorRef RI);
// NOTE: Caller takes ownership of returned string of the two
// following functions.
const(char) *LLVMGetRelocationTypeName(LLVMRelocationIteratorRef RI);
const(char) *LLVMGetRelocationValueString(LLVMRelocationIteratorRef RI);

/**
 * @}
 */
