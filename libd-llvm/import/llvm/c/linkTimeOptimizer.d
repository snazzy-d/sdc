//===-- llvm/LinkTimeOptimizer.h - LTO Public C Interface -------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
// 
//===----------------------------------------------------------------------===//
//
// This header provides a C API to use the LLVM link time optimization
// library. This is intended to be used by linkers which are C-only in
// their implementation for performing LTO.
//
//===----------------------------------------------------------------------===//

module llvm.c.linkTimeOptimizer;

import llvm.c.core;

extern(C) nothrow:

/**
 * @defgroup LLVMCLinkTimeOptimizer Link Time Optimization
 * @ingroup LLVMC
 *
 * @{
 */

  /// This provides a dummy type for pointers to the LTO object.
  alias void* llvm_lto_t;

  /// This provides a C-visible enumerator to manage status codes.
  /// This should map exactly onto the C++ enumerator LTOStatus.
  enum llvm_lto_status {
    UNKNOWN,
    OPT_SUCCESS,
    READ_SUCCESS,
    READ_FAILURE,
    WRITE_FAILURE,
    NO_TARGET,
    NO_WORK,
    MODULE_MERGE_FAILURE,
    ASM_FAILURE,

    //  Added C-specific error codes
    NULL_OBJECT
  }
  alias llvm_lto_status llvm_lto_status_t;
 
  /// This provides C interface to initialize link time optimizer. This allows
  /// linker to use dlopen() interface to dynamically load LinkTimeOptimizer.
  /// extern "C" helps, because dlopen() interface uses name to find the symbol.
  extern llvm_lto_t llvm_create_optimizer();
  extern void llvm_destroy_optimizer(llvm_lto_t lto);

  extern llvm_lto_status_t llvm_read_object_file
    (llvm_lto_t lto, const(char)* input_filename);
  extern llvm_lto_status_t llvm_optimize_modules
    (llvm_lto_t lto, const(char)* output_filename);

/**
 * @}
 */
