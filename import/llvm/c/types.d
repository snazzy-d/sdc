/*===-- llvm-c/Support.h - C Interface Types declarations ---------*- C -*-===*\
|*                                                                            *|
|*                     The LLVM Compiler Infrastructure                       *|
|*                                                                            *|
|* This file is distributed under the University of Illinois Open Source      *|
|* License. See LICENSE.TXT for details.                                      *|
|*                                                                            *|
|*===----------------------------------------------------------------------===*|
|*                                                                            *|
|* This file defines types used by the the C interface to LLVM.               *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

module llvm.c.types;

extern(C) nothrow:

/**
 * @defgroup LLVMCSupportTypes Types and Enumerations
 *
 * @{
 */

alias LLVMBool = int;

/* Opaque types. */

/**
 * LLVM uses a polymorphic type hierarchy which C cannot represent, therefore
 * parameters must be passed as base types. Despite the declared types, most
 * of the functions provided operate only on branches of the type hierarchy.
 * The declared parameter names are descriptive and specify which type is
 * required. Additionally, each type hierarchy is documented along with the
 * functions that operate upon it. For more detail, refer to LLVM's C++ code.
 * If in doubt, refer to Core.cpp, which performs parameter downcasts in the
 * form unwrap<RequiredType>(Param).
 */

/**
 * Used to pass regions of memory through LLVM interfaces.
 *
 * @see llvm::MemoryBuffer
 */
struct __LLVMOpaqueMemoryBuffer {};
alias LLVMMemoryBufferRef = __LLVMOpaqueMemoryBuffer*;

/**
 * The top-level container for all LLVM global data. See the LLVMContext class.
 */
struct __LLVMOpaqueContext {};
alias LLVMContextRef = __LLVMOpaqueContext*;

/**
 * The top-level container for all other LLVM Intermediate Representation (IR)
 * objects.
 *
 * @see llvm::Module
 */
struct __LLVMOpaqueModule {};
alias LLVMModuleRef = __LLVMOpaqueModule*;

/**
 * Each value in the LLVM IR has a type, an LLVMTypeRef.
 *
 * @see llvm::Type
 */
struct __LLVMOpaqueType {};
alias LLVMTypeRef = __LLVMOpaqueType*;

/**
 * Represents an individual value in LLVM IR.
 *
 * This models llvm::Value.
 */
struct __LLVMOpaqueValue {};
alias LLVMValueRef = __LLVMOpaqueValue*;

/**
 * Represents a basic block of instructions in LLVM IR.
 *
 * This models llvm::BasicBlock.
 */
struct __LLVMOpaqueBasicBlock {};
alias LLVMBasicBlockRef = __LLVMOpaqueBasicBlock*;

/**
 * Represents an LLVM Metadata.
 *
 * This models llvm::Metadata.
 */
struct __LLVMOpaqueMetadata {};
alias LLVMMetadataRef = __LLVMOpaqueMetadata*;

/**
 * Represents an LLVM Named Metadata Node.
 *
 * This models llvm::NamedMDNode.
 */
struct __LLVMOpaqueNamedMDNode {};
alias LLVMNamedMDNodeRef = __LLVMOpaqueNamedMDNode*;

/**
 * Represents an entry in a Global Object's metadata attachments.
 *
 * This models std::pair<unsigned, MDNode *>
 */
struct __LLVMOpaqueValueMetadataEntry {};
alias LLVMValueMetadataEntry = __LLVMOpaqueValueMetadataEntry*;

/**
 * Represents an LLVM basic block builder.
 *
 * This models llvm::IRBuilder.
 */
struct __LLVMOpaqueBuilder {};
alias LLVMBuilderRef = __LLVMOpaqueBuilder*;

/**
 * Represents an LLVM debug info builder.
 *
 * This models llvm::DIBuilder.
 */
struct __LLVMOpaqueDIBuilder {};
alias LLVMDIBuilderRef = __LLVMOpaqueDIBuilder*;

/**
 * Interface used to provide a module to JIT or interpreter.
 * This is now just a synonym for llvm::Module, but we have to keep using the
 * different type to keep binary compatibility.
 */
struct __LLVMOpaqueModuleProvider {};
alias LLVMModuleProviderRef = __LLVMOpaqueModuleProvider*;

/** @see llvm::PassManagerBase */
struct __LLVMOpaquePassManager {};
alias LLVMPassManagerRef = __LLVMOpaquePassManager*;

/** @see llvm::PassRegistry */
struct __LLVMOpaquePassRegistry {};
alias __LLVMOpaquePassRegistry *LLVMPassRegistryRef;

/**
 * Used to get the users and usees of a Value.
 *
 * @see llvm::Use */
struct __LLVMOpaqueUse {};
alias LLVMUseRef = __LLVMOpaqueUse*;

/**
 * Used to represent an attributes.
 *
 * @see llvm::Attribute
 */
struct __LLVMOpaqueAttribute {};
alias LLVMAttributeRef = __LLVMOpaqueAttribute*;

/**
 * @see llvm::DiagnosticInfo
 */
struct __LLVMOpaqueDiagnosticInfo {};
alias LLVMDiagnosticInfoRef = __LLVMOpaqueDiagnosticInfo*;

/**
 * @see llvm::Comdat
 */
struct __LLVMComdat {};
alias LLVMComdatRef = __LLVMComdat*;

/**
 * @see llvm::Module::ModuleFlagEntry
 */
struct __LLVMOpaqueModuleFlagEntry {};
alias LLVMModuleFlagEntry = __LLVMOpaqueModuleFlagEntry*;

/**
 * @see llvm::JITEventListener
 */
struct __LLVMOpaqueJITEventListener {};
alias LLVMJITEventListenerRef = __LLVMOpaqueJITEventListener*;

/**
 * @see llvm::object::Binary
 */
struct __LLVMOpaqueBinary {};
alias LLVMBinaryRef = __LLVMOpaqueBinary*;

/**
 * @}
 */

