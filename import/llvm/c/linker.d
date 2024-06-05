/*===-- llvm-c/Linker.h - Module Linker C Interface -------------*- C++ -*-===*\
|*                                                                            *|
|* Part of the LLVM Project, under the Apache License v2.0 with LLVM          *|
|* Exceptions.                                                                *|
|* See https://llvm.org/LICENSE.txt for license information.                  *|
|* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception                    *|
|*                                                                            *|
|*===----------------------------------------------------------------------===*|
|*                                                                            *|
|* This file defines the C interface to the module/file/archive linker.       *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

module llvm.c.linker;

public import llvm.c.types;

extern(C) nothrow:

/**
 * @defgroup LLVMCCoreLinker Linker
 * @ingroup LLVMCCore
 *
 * @{
 */

enum LLVMLinkerMode {
  DestroySource = 0, /* This is the default behavior. */
  PreserveSource_Removed = 1, /* This option has been deprecated and
                                 should not be used. */
}

/* Links the source module into the destination module. The source module is
 * destroyed.
 * The return value is true if an error occurred, false otherwise.
 * Use the diagnostic handler to get any diagnostic message.
*/
LLVMBool LLVMLinkModules2(LLVMModuleRef Dest, LLVMModuleRef Src);

/**
 * @}
 */
