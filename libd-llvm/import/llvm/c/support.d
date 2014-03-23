/*===-- llvm-c/Support.h - Support C Interface --------------------*- C -*-===*\
|*                                                                            *|
|*                     The LLVM Compiler Infrastructure                       *|
|*                                                                            *|
|* This file is distributed under the University of Illinois Open Source      *|
|* License. See LICENSE.TXT for details.                                      *|
|*                                                                            *|
|*===----------------------------------------------------------------------===*|
|*                                                                            *|
|* This file defines the C interface to the LLVM support library.             *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

module llvm.c.support;

import llvm.c.core;

extern(C) nothrow:

/**
 * This function permanently loads the dynamic library at the given path.
 * It is safe to call this function multiple times for the same library.
 *
 * @see sys::DynamicLibrary::LoadLibraryPermanently()
  */
LLVMBool LLVMLoadLibraryPermanently(const(char)* Filename);

