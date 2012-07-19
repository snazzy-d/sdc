/*===-- llvm-c/Core.h - Core Library C Interface ------------------*- D -*-===*\
|*                                                                            *|
|*                     The LLVM Compiler Infrastructure                       *|
|*                                                                            *|
|* This file is distributed under the University of Illinois Open Source      *|
|* License. See LICENSE.TXT for details.                                      *|
|*                                                                            *|
|*===----------------------------------------------------------------------===*|
|*                                                                            *|
|* This header declares the C interface to libLLVMCore.a, which implements    *|
|* the LLVM intermediate representation.                                      *|
|*                                                                            *|
|* LLVM uses a polymorphic type hierarchy which C cannot represent, therefore *|
|* parameters must be passed as base types. Despite the declared types, most  *|
|* of the functions provided operate only on branches of the type hierarchy.  *|
|* The declared parameter names are descriptive and specify which type is     *|
|* required. Additionally, each type hierarchy is documented along with the   *|
|* functions that operate upon it. For more detail, refer to LLVM's C++ code. *|
|* If in doubt, refer to Core.cpp, which performs paramter downcasts in the   *|
|* form unwrap<RequiredType>(Param).                                          *|
|*                                                                            *|
|* Many exotic languages can interoperate with C code but have a harder time  *|
|* with C++ due to name mangling. So in addition to C, this interface enables *|
|* tools written in such languages.                                           *|
|*                                                                            *|
|* When included into a C++ source file, also declares 'wrap' and 'unwrap'    *|
|* helpers to perform opaque reference<-->pointer conversions. These helpers  *|
|* are shorter and more tightly typed than writing the casts by hand when     *|
|* authoring bindings. In assert builds, they will do runtime type checking.  *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/
module llvm.c.Core;


extern(C):


alias int LLVMBool;

/* Opaque types. */

/**
 * The top-level container for all LLVM global data.  See the LLVMContext class.
 */
struct __LLVMOpaqueContext {}
alias __LLVMOpaqueContext* LLVMContextRef;

/**
 * The top-level container for all other LLVM Intermediate Representation (IR)
 * objects. See the llvm::Module class.
 */
struct __LLVMOpaqueModule {}
alias __LLVMOpaqueModule* LLVMModuleRef;

/**
 * Each value in the LLVM IR has a type, an LLVMTypeRef. See the llvm::Type
 * class.
 */
struct __LLVMOpaqueType {}
alias __LLVMOpaqueType* /*int**/ LLVMTypeRef;

struct __LLVMOpaqueValue {}
alias __LLVMOpaqueValue* /*int**/ LLVMValueRef;

//struct __LLVMOpaqueBasicBlock {}
alias /*__LLVMOpaqueBasicBlock*/ int* LLVMBasicBlockRef;

struct __LLVMOpaqueBuilder {}
alias __LLVMOpaqueBuilder* LLVMBuilderRef;

/* Interface used to provide a module to JIT or interpreter.  This is now just a
 * synonym for llvm::Module, but we have to keep using the different type to
 * keep binary compatibility.
 */
struct __LLVMOpaqueModuleProvider {}
alias __LLVMOpaqueModuleProvider* LLVMModuleProviderRef;

/* Used to provide a module to JIT or interpreter.
 * See the llvm::MemoryBuffer class.
 */
struct __LLVMOpaqueMemoryBuffer {}
alias __LLVMOpaqueMemoryBuffer* LLVMMemoryBufferRef;

/** See the llvm::PassManagerBase class. */
struct __LLVMOpaquePassManager {}
alias __LLVMOpaquePassManager* LLVMPassManagerRef;

/** See the llvm::PassRegistry class. */
struct __LLVMOpaquePassRegistry {}
alias  __LLVMOpaquePassRegistry* LLVMPassRegistryRef;

/** Used to get the users and usees of a Value. See the llvm::Use class. */
struct __LLVMOpaqueUse {}
alias __LLVMOpaqueUse* LLVMUseRef;

enum LLVMAttribute {
    ZExt       = 1<<0,
    SExt       = 1<<1,
    NoReturn   = 1<<2,
    InReg      = 1<<3,
    StructRet  = 1<<4,
    NoUnwind   = 1<<5,
    NoAlias    = 1<<6,
    ByVal      = 1<<7,
    Nest       = 1<<8,
    ReadNone   = 1<<9,
    ReadOnly   = 1<<10,
    NoInline   = 1<<11,
    AlwaysInline    = 1<<12,
    OptimizeForSize = 1<<13,
    StackProtect    = 1<<14,
    StackProtectReq = 1<<15,
    Alignment = 31<<16,
    NoCapture  = 1<<21,
    NoRedZone  = 1<<22,
    NoImplicitFloat = 1<<23,
    Naked      = 1<<24,
    InlineHint = 1<<25,
    StackAlignment = 7<<26,
    ReturnsTwice = 1 << 29,
    UWTable = 1 << 30,
    NonLazyBind = 1 << 31
}

enum LLVMOpcode {
  /* Terminator Instructions */
  Ret            = 1,
  Br             = 2,
  Switch         = 3,
  IndirectBr     = 4,
  Invoke         = 5,
  /* removed 6 due to API changes */
  Unreachable    = 7,

  /* Standard Binary Operators */
  Add            = 8,
  FAdd           = 9,
  Sub            = 10,
  FSub           = 11,
  Mul            = 12,
  FMul           = 13,
  UDiv           = 14,
  SDiv           = 15,
  FDiv           = 16,
  URem           = 17,
  SRem           = 18,
  FRem           = 19,

  /* Logical Operators */
  Shl            = 20,
  LShr           = 21,
  AShr           = 22,
  And            = 23,
  Or             = 24,
  Xor            = 25,

  /* Memory Operators */
  Alloca         = 26,
  Load           = 27,
  Store          = 28,
  GetElementPtr  = 29,

  /* Cast Operators */
  Trunc          = 30,
  ZExt           = 31,
  SExt           = 32,
  FPToUI         = 33,
  FPToSI         = 34,
  UIToFP         = 35,
  SIToFP         = 36,
  FPTrunc        = 37,
  FPExt          = 38,
  PtrToInt       = 39,
  IntToPtr       = 40,
  BitCast        = 41,

  /* Other Operators */
  ICmp           = 42,
  FCmp           = 43,
  PHI            = 44,
  Call           = 45,
  Select         = 46,
  UserOp1        = 47,
  UserOp2        = 48,
  VAArg          = 49,
  ExtractElement = 50,
  InsertElement  = 51,
  ShuffleVector  = 52,
  ExtractValue   = 53,
  InsertValue    = 54,

  /* Atomic operators */
  LLVMFence          = 55,
  LLVMAtomicCmpXchg  = 56,
  LLVMAtomicRMW      = 57,

  /* Exception Handling Operators */
  LLVMResume         = 58,
  LLVMLandingPad     = 59,
  LLVMUnwind         = 60
}

enum LLVMTypeKind {
  Void,        /**< type with no size */
  Float,       /**< 32 bit floating point type */
  Double,      /**< 64 bit floating point type */
  X86_FP80,    /**< 80 bit floating point type (X87) */
  FP128,       /**< 128 bit floating point type (112-bit mantissa) */
  PPC_FP128,   /**< 128 bit floating point type (two 64-bits) */
  Label,       /**< Labels */
  Integer,     /**< Arbitrary bit width integers */
  Function,    /**< Functions */
  Struct,      /**< Structures */
  Array,       /**< Arrays */
  Pointer,     /**< Pointers */
  Vector,      /**< SIMD 'packed' format, or other vector type */
  Metadata,     /**< Metadata */
  X86_MMX      /**< X86 MMX */
}

enum LLVMLinkage {
  External,                /**< Externally visible function */
  AvailableExternally,
  LinkOnceAny,             /**< Keep one copy of function when linking (inline) */
  LinkOnceODR,             /**< Same, but only replaced by something equivalent. */
  WeakAny,                 /**< Keep one copy of function when linking (weak) */
  WeakODR,                 /**< Same, but only replaced by something equivalent. */
  Appending,               /**< Special purpose, only applies to global arrays */
  Internal,                /**< Rename collisions when linking (static functions) */
  Private,                 /**< Like Internal, but omit from symbol table */
  DLLImport,               /**< Function to be imported from DLL */
  DLLExport,               /**< Function to be accessible from DLL */
  ExternalWeak,            /**< ExternalWeak linkage description */
  Ghost,                   /**< Obsolete */
  Common,                  /**< Tentative definitions */
  LinkerPrivate,           /**< Like Private, but linker removes. */
  LinkerPrivateWeak,       /**< Like LinkerPrivate, but is weak. */
  LinkerPrivateWeakDefAuto /**< Like LinkerPrivateWeak, but possibly hidden. */
}

enum LLVMVisibility {
  Default,  /**< The GV is visible */
  Hidden,   /**< The GV is hidden */
  Protected /**< The GV is protected */
}

enum LLVMCallConv {
  C           = 0,
  Fast        = 8,
  Cold        = 9,
  X86Stdcall  = 64,
  X86Fastcall = 65
}

enum LLVMIntPredicate {
  EQ = 32, /**< equal */
  NE,      /**< not equal */
  UGT,     /**< unsigned greater than */
  UGE,     /**< unsigned greater or equal */
  ULT,     /**< unsigned less than */
  ULE,     /**< unsigned less or equal */
  SGT,     /**< signed greater than */
  SGE,     /**< signed greater or equal */
  SLT,     /**< signed less than */
  SLE      /**< signed less or equal */
}

enum LLVMRealPredicate {
  False, /**< Always false (always folded) */
  OEQ,   /**< True if ordered and equal */
  OGT,   /**< True if ordered and greater than */
  OGE,   /**< True if ordered and greater than or equal */
  OLT,   /**< True if ordered and less than */
  OLE,   /**< True if ordered and less than or equal */
  ONE,   /**< True if ordered and operands are unequal */
  ORD,   /**< True if ordered (no nans) */
  UNO,   /**< True if unordered: isnan(X) | isnan(Y) */
  UEQ,   /**< True if unordered or equal */
  UGT,   /**< True if unordered or greater than */
  UGE,   /**< True if unordered, greater than, or equal */
  ULT,   /**< True if unordered or less than */
  ULE,   /**< True if unordered, less than, or equal */
  UNE,   /**< True if unordered or not equal */
  True   /**< Always true (always folded) */
}

enum LLVMLandingPadClauseTy {
  Catch,    /**< A catch clause   */
  Filter    /**< A filter clause  */
}

void LLVMInitializeCore(LLVMPassRegistryRef R);


/*===-- Error handling ----------------------------------------------------===*/

void LLVMDisposeMessage(char* Message);


/*===-- Contexts ----------------------------------------------------------===*/

/* Create and destroy contexts. */
LLVMContextRef LLVMContextCreate();
LLVMContextRef LLVMGetGlobalContext();
void LLVMContextDispose(LLVMContextRef C);

uint LLVMGetMDKindIDInContext(LLVMContextRef C, /*const*/ const(char)* Name,
                                  uint SLen);
uint LLVMGetMDKindID(/*const*/ const(char)* Name, uint SLen);

/*===-- Modules -----------------------------------------------------------===*/

/* Create and destroy modules. */
/** See llvm::Module::Module. */
LLVMModuleRef LLVMModuleCreateWithName(/*const*/ const(char)* ModuleID);
LLVMModuleRef LLVMModuleCreateWithNameInContext(/*const*/ const(char)* ModuleID,
                                                LLVMContextRef C);

/** See llvm::Module::~Module. */
void LLVMDisposeModule(LLVMModuleRef M);

/** Data layout. See Module::getDataLayout. */
/*const*/ const(char)* LLVMGetDataLayout(LLVMModuleRef M);
void LLVMSetDataLayout(LLVMModuleRef M, /*const*/ const(char)* Triple);

/** Target triple. See Module::getTargetTriple. */
/*const*/ const(char)* LLVMGetTarget(LLVMModuleRef M);
void LLVMSetTarget(LLVMModuleRef M, /*const*/ const(char)* Triple);

/** See Module::dump. */
void LLVMDumpModule(LLVMModuleRef M);

/** See Module::setModuleInlineAsm. */
void LLVMSetModuleInlineAsm(LLVMModuleRef M, /*const*/ const(char)* Asm);

/** See Module::getContext. */
LLVMContextRef LLVMGetModuleContext(LLVMModuleRef M);

/*===-- Types -------------------------------------------------------------===*/

/* LLVM types conform to the following hierarchy:
 *
 *   types:
 *     integer type
 *     real type
 *     function type
 *     sequence types:
 *       array type
 *       pointer type
 *       vector type
 *     void type
 *     label type
 *     opaque type
 */

/** See llvm::LLVMTypeKind::getTypeID. */
LLVMTypeKind LLVMGetTypeKind(LLVMTypeRef Ty);
LLVMBool LLVMTypeIsSized(LLVMTypeRef Ty);

/** See llvm::LLVMType::getContext. */
LLVMContextRef LLVMGetTypeContext(LLVMTypeRef Ty);

/* Operations on integer types */
LLVMTypeRef LLVMInt1TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMInt8TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMInt16TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMInt32TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMInt64TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMIntTypeInContext(LLVMContextRef C, uint NumBits);

LLVMTypeRef LLVMInt1Type();
LLVMTypeRef LLVMInt8Type();
LLVMTypeRef LLVMInt16Type();
LLVMTypeRef LLVMInt32Type();
LLVMTypeRef LLVMInt64Type();
LLVMTypeRef LLVMIntType(uint NumBits);
uint LLVMGetIntTypeWidth(LLVMTypeRef IntegerTy);

/* Operations on real types */
LLVMTypeRef LLVMFloatTypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMDoubleTypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMX86FP80TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMFP128TypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMPPCFP128TypeInContext(LLVMContextRef C);

LLVMTypeRef LLVMFloatType();
LLVMTypeRef LLVMDoubleType();
LLVMTypeRef LLVMX86FP80Type();
LLVMTypeRef LLVMFP128Type();
LLVMTypeRef LLVMPPCFP128Type();

/* Operations on function types */
LLVMTypeRef LLVMFunctionType(LLVMTypeRef ReturnType,
                             LLVMTypeRef* ParamTypes, uint ParamCount,
                             LLVMBool IsVarArg);
LLVMBool LLVMIsFunctionVarArg(LLVMTypeRef FunctionTy);
LLVMTypeRef LLVMGetReturnType(LLVMTypeRef FunctionTy);
uint LLVMCountParamTypes(LLVMTypeRef FunctionTy);
void LLVMGetParamTypes(LLVMTypeRef FunctionTy, LLVMTypeRef* Dest);

/* Operations on struct types */
LLVMTypeRef LLVMStructTypeInContext(LLVMContextRef C, LLVMTypeRef* ElementTypes,
                                    uint ElementCount, LLVMBool Packed);
LLVMTypeRef LLVMStructType(LLVMTypeRef* ElementTypes, uint ElementCount,
                           LLVMBool Packed);
LLVMTypeRef LLVMStructCreateNamed(LLVMContextRef C, /*const*/ char* Name);
/*const*/ char* LLVMGetStructName(LLVMTypeRef Ty);
void LLVMStructSetBody(LLVMTypeRef StructTy, LLVMTypeRef* ElementTypes,
                       uint ElementCount, LLVMBool Packed);

uint LLVMCountStructElementTypes(LLVMTypeRef StructTy);
void LLVMGetStructElementTypes(LLVMTypeRef StructTy, LLVMTypeRef* Dest);
LLVMBool LLVMIsPackedStruct(LLVMTypeRef StructTy);
LLVMBool LLVMIsOpaqueStruct(LLVMTypeRef StructTy);

LLVMTypeRef LLVMGetTypeByName(LLVMModuleRef M, /*const*/ char* Name);

/* Operations on array, pointer, and vector types (sequence types) */
LLVMTypeRef LLVMArrayType(LLVMTypeRef ElementType, uint ElementCount);
LLVMTypeRef LLVMPointerType(LLVMTypeRef ElementType, uint AddressSpace);
LLVMTypeRef LLVMVectorType(LLVMTypeRef ElementType, uint ElementCount);

LLVMTypeRef LLVMGetElementType(LLVMTypeRef Ty);
uint LLVMGetArrayLength(LLVMTypeRef ArrayTy);
uint LLVMGetPointerAddressSpace(LLVMTypeRef PointerTy);
uint LLVMGetVectorSize(LLVMTypeRef VectorTy);

/* Operations on other types */
LLVMTypeRef LLVMVoidTypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMLabelTypeInContext(LLVMContextRef C);
LLVMTypeRef LLVMX86MMXTypeInContext(LLVMContextRef C);

LLVMTypeRef LLVMVoidType();
LLVMTypeRef LLVMLabelType();
LLVMTypeRef LLVMX86MMXType();


/*===-- Values ------------------------------------------------------------===*/

/* The bulk of LLVM's object model consists of values, which comprise a very
 * rich type hierarchy.
 */
// macros were removed for these bindings

/* Operations on all values */
LLVMTypeRef LLVMTypeOf(LLVMValueRef Val);
/*const*/ const(char)* LLVMGetValueName(LLVMValueRef Val);
void LLVMSetValueName(LLVMValueRef Val, /*const*/ const(char)* Name);
void LLVMDumpValue(LLVMValueRef Val);
void LLVMReplaceAllUsesWith(LLVMValueRef OldVal, LLVMValueRef NewVal);
int LLVMHasMetadata(LLVMValueRef Val);
LLVMValueRef LLVMGetMetadata(LLVMValueRef Val, uint KindID);
void LLVMSetMetadata(LLVMValueRef Val, uint KindID, LLVMValueRef Node);

/* Conversion functions. Return the input value if it is an instance of the
   specified class, otherwise NULL. See llvm::dyn_cast_or_null<>. */
/*
#define LLVM_DECLARE_VALUE_CAST(name) \
  LLVMValueRef LLVMIsA##name(LLVMValueRef Val);
LLVM_FOR_EACH_VALUE_SUBCLASS(LLVM_DECLARE_VALUE_CAST)
*/

/* Operations on Uses */
LLVMUseRef LLVMGetFirstUse(LLVMValueRef Val);
LLVMUseRef LLVMGetNextUse(LLVMUseRef U);
LLVMValueRef LLVMGetUser(LLVMUseRef U);
LLVMValueRef LLVMGetUsedValue(LLVMUseRef U);

/* Operations on Users */
LLVMValueRef LLVMGetOperand(LLVMValueRef Val, uint Index);
void LLVMSetOperand(LLVMValueRef User, uint Index, LLVMValueRef Val);
int LLVMGetNumOperands(LLVMValueRef Val);

/* Operations on constants of any type */
LLVMValueRef LLVMConstNull(LLVMTypeRef Ty); /* all zeroes */
LLVMValueRef LLVMConstAllOnes(LLVMTypeRef Ty); /* only for int/vector */
LLVMValueRef LLVMGetUndef(LLVMTypeRef Ty);
LLVMBool LLVMIsConstant(LLVMValueRef Val);
LLVMBool LLVMIsNull(LLVMValueRef Val);
LLVMBool LLVMIsUndef(LLVMValueRef Val);
LLVMValueRef LLVMConstPointerNull(LLVMTypeRef Ty);

/* Operations on metadata */
LLVMValueRef LLVMMDStringInContext(LLVMContextRef C, /*const*/ const(char)* Str,
                                   uint SLen);
LLVMValueRef LLVMMDString(/*const*/ const(char)* Str, uint SLen);
LLVMValueRef LLVMMDNodeInContext(LLVMContextRef C, LLVMValueRef* Vals,
                                 uint Count);
LLVMValueRef LLVMMDNode(LLVMValueRef* Vals, uint Count);
/*const*/ char* LLVMGetMDString(LLVMValueRef V, uint* Len);
int LLVMGetMDNodeNumOperands(LLVMValueRef V);
LLVMValueRef *LLVMGetMDNodeOperand(LLVMValueRef V, uint i);
uint LLVMGetNamedMetadataNumOperands(LLVMModuleRef M, /*const*/ char* name);
void LLVMGetNamedMetadataOperands(LLVMModuleRef M, /*const*/ char* name, LLVMValueRef *Dest);

/* Operations on scalar constants */
LLVMValueRef LLVMConstInt(LLVMTypeRef IntTy, ulong N,
                          LLVMBool SignExtend);
LLVMValueRef LLVMConstIntOfArbitraryPrecision(LLVMTypeRef IntTy,
                                              uint NumWords,
                                              /*const*/ ulong* Words);
LLVMValueRef LLVMConstIntOfString(LLVMTypeRef IntTy, /*const*/ const(char)* Text,
                                  ubyte Radix);
LLVMValueRef LLVMConstIntOfStringAndSize(LLVMTypeRef IntTy, /*const*/ const(char)* Text,
                                         uint SLen, ubyte Radix);
LLVMValueRef LLVMConstReal(LLVMTypeRef RealTy, double N);
LLVMValueRef LLVMConstRealOfString(LLVMTypeRef RealTy, /*const*/ const(char)* Text);
LLVMValueRef LLVMConstRealOfStringAndSize(LLVMTypeRef RealTy, /*const*/ const(char)* Text,
                                          uint SLen);
ulong LLVMConstIntGetZExtValue(LLVMValueRef ConstantVal);
long LLVMConstIntGetSExtValue(LLVMValueRef ConstantVal);


/* Operations on composite constants */
LLVMValueRef LLVMConstStringInContext(LLVMContextRef C, /*const*/ const(char)* Str,
                                      uint Length, LLVMBool DontNullTerminate);
LLVMValueRef LLVMConstStructInContext(LLVMContextRef C,
                                      LLVMValueRef* ConstantVals,
                                      uint Count, LLVMBool Packed);

LLVMValueRef LLVMConstString(/*const*/ const(char)* Str, uint Length,
                             LLVMBool DontNullTerminate);
LLVMValueRef LLVMConstArray(LLVMTypeRef ElementTy,
                            LLVMValueRef* ConstantVals, uint Length);
LLVMValueRef LLVMConstStruct(LLVMValueRef* ConstantVals, uint Count,
                             LLVMBool Packed);
LLVMValueRef LLVMConstNamedStruct(LLVMTypeRef StructTy,
                                  LLVMValueRef *ConstantVals,
                                  uint Count);
LLVMValueRef LLVMConstVector(LLVMValueRef* ScalarConstantVals, uint Size);

/* Constant expressions */
LLVMOpcode LLVMGetConstOpcode(LLVMValueRef ConstantVal);
LLVMValueRef LLVMAlignOf(LLVMTypeRef Ty);
LLVMValueRef LLVMSizeOf(LLVMTypeRef Ty);
LLVMValueRef LLVMConstNeg(LLVMValueRef ConstantVal);
LLVMValueRef LLVMConstNSWNeg(LLVMValueRef ConstantVal);
LLVMValueRef LLVMConstNUWNeg(LLVMValueRef ConstantVal);
LLVMValueRef LLVMConstFNeg(LLVMValueRef ConstantVal);
LLVMValueRef LLVMConstNot(LLVMValueRef ConstantVal);
LLVMValueRef LLVMConstAdd(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstNSWAdd(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstNUWAdd(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstFAdd(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstSub(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstNSWSub(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstNUWSub(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstFSub(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstMul(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstNSWMul(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstNUWMul(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstFMul(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstUDiv(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstSDiv(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstExactSDiv(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstFDiv(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstURem(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstSRem(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstFRem(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstAnd(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstOr(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstXor(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstICmp(LLVMIntPredicate Predicate,
                           LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstFCmp(LLVMRealPredicate Predicate,
                           LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstShl(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstLShr(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstAShr(LLVMValueRef LHSConstant, LLVMValueRef RHSConstant);
LLVMValueRef LLVMConstGEP(LLVMValueRef ConstantVal,
                          LLVMValueRef* ConstantIndices, uint NumIndices);
LLVMValueRef LLVMConstInBoundsGEP(LLVMValueRef ConstantVal,
                                  LLVMValueRef* ConstantIndices,
                                  uint NumIndices);
LLVMValueRef LLVMConstTrunc(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstSExt(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstZExt(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstFPTrunc(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstFPExt(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstUIToFP(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstSIToFP(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstFPToUI(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstFPToSI(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstPtrToInt(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstIntToPtr(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstBitCast(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstZExtOrBitCast(LLVMValueRef ConstantVal,
                                    LLVMTypeRef ToType);
LLVMValueRef LLVMConstSExtOrBitCast(LLVMValueRef ConstantVal,
                                    LLVMTypeRef ToType);
LLVMValueRef LLVMConstTruncOrBitCast(LLVMValueRef ConstantVal,
                                     LLVMTypeRef ToType);
LLVMValueRef LLVMConstPointerCast(LLVMValueRef ConstantVal,
                                  LLVMTypeRef ToType);
LLVMValueRef LLVMConstIntCast(LLVMValueRef ConstantVal, LLVMTypeRef ToType,
                              LLVMBool isSigned);
LLVMValueRef LLVMConstFPCast(LLVMValueRef ConstantVal, LLVMTypeRef ToType);
LLVMValueRef LLVMConstSelect(LLVMValueRef ConstantCondition,
                             LLVMValueRef ConstantIfTrue,
                             LLVMValueRef ConstantIfFalse);
LLVMValueRef LLVMConstExtractElement(LLVMValueRef VectorConstant,
                                     LLVMValueRef IndexConstant);
LLVMValueRef LLVMConstInsertElement(LLVMValueRef VectorConstant,
                                    LLVMValueRef ElementValueConstant,
                                    LLVMValueRef IndexConstant);
LLVMValueRef LLVMConstShuffleVector(LLVMValueRef VectorAConstant,
                                    LLVMValueRef VectorBConstant,
                                    LLVMValueRef MaskConstant);
LLVMValueRef LLVMConstExtractValue(LLVMValueRef AggConstant, uint *IdxList,
                                   uint NumIdx);
LLVMValueRef LLVMConstInsertValue(LLVMValueRef AggConstant,
                                  LLVMValueRef ElementValueConstant,
                                  uint *IdxList, uint NumIdx);
LLVMValueRef LLVMConstInlineAsm(LLVMTypeRef Ty,
                                /*const*/ const(char)* AsmString, /*const*/ const(char)* Constraints,
                                LLVMBool HasSideEffects, LLVMBool IsAlignStack);
LLVMValueRef LLVMBlockAddress(LLVMValueRef F, LLVMBasicBlockRef BB);

/* Operations on global variables, functions, and aliases (globals) */
LLVMModuleRef LLVMGetGlobalParent(LLVMValueRef Global);
LLVMBool LLVMIsDeclaration(LLVMValueRef Global);
LLVMLinkage LLVMGetLinkage(LLVMValueRef Global);
void LLVMSetLinkage(LLVMValueRef Global, LLVMLinkage Linkage);
/*const*/ const(char)* LLVMGetSection(LLVMValueRef Global);
void LLVMSetSection(LLVMValueRef Global, /*const*/ const(char)* Section);
LLVMVisibility LLVMGetVisibility(LLVMValueRef Global);
void LLVMSetVisibility(LLVMValueRef Global, LLVMVisibility Viz);
uint LLVMGetAlignment(LLVMValueRef Global);
void LLVMSetAlignment(LLVMValueRef Global, uint Bytes);

/* Operations on global variables */
LLVMValueRef LLVMAddGlobal(LLVMModuleRef M, LLVMTypeRef Ty, /*const*/ const(char)* Name);
LLVMValueRef LLVMAddGlobalInAddressSpace(LLVMModuleRef M, LLVMTypeRef Ty,
                                         /*const*/ const(char)* Name,
                                         uint AddressSpace);
LLVMValueRef LLVMGetNamedGlobal(LLVMModuleRef M, /*const*/ const(char)* Name);
LLVMValueRef LLVMGetFirstGlobal(LLVMModuleRef M);
LLVMValueRef LLVMGetLastGlobal(LLVMModuleRef M);
LLVMValueRef LLVMGetNextGlobal(LLVMValueRef GlobalVar);
LLVMValueRef LLVMGetPreviousGlobal(LLVMValueRef GlobalVar);
void LLVMDeleteGlobal(LLVMValueRef GlobalVar);
LLVMValueRef LLVMGetInitializer(LLVMValueRef GlobalVar);
void LLVMSetInitializer(LLVMValueRef GlobalVar, LLVMValueRef ConstantVal);
LLVMBool LLVMIsThreadLocal(LLVMValueRef GlobalVar);
void LLVMSetThreadLocal(LLVMValueRef GlobalVar, LLVMBool IsThreadLocal);
LLVMBool LLVMIsGlobalConstant(LLVMValueRef GlobalVar);
void LLVMSetGlobalConstant(LLVMValueRef GlobalVar, LLVMBool IsConstant);

/* Operations on aliases */
LLVMValueRef LLVMAddAlias(LLVMModuleRef M, LLVMTypeRef Ty, LLVMValueRef Aliasee,
                          /*const*/ const(char)* Name);

/* Operations on functions */
LLVMValueRef LLVMAddFunction(LLVMModuleRef M, /*const*/ const(char)* Name,
                             LLVMTypeRef FunctionTy);
LLVMValueRef LLVMGetNamedFunction(LLVMModuleRef M, /*const*/ const(char)* Name);
LLVMValueRef LLVMGetFirstFunction(LLVMModuleRef M);
LLVMValueRef LLVMGetLastFunction(LLVMModuleRef M);
LLVMValueRef LLVMGetNextFunction(LLVMValueRef Fn);
LLVMValueRef LLVMGetPreviousFunction(LLVMValueRef Fn);
void LLVMDeleteFunction(LLVMValueRef Fn);
uint LLVMGetIntrinsicID(LLVMValueRef Fn);
uint LLVMGetFunctionCallConv(LLVMValueRef Fn);
void LLVMSetFunctionCallConv(LLVMValueRef Fn, uint CC);
/*const*/ const(char)* LLVMGetGC(LLVMValueRef Fn);
void LLVMSetGC(LLVMValueRef Fn, /*const*/ const(char)* Name);
void LLVMAddFunctionAttr(LLVMValueRef Fn, LLVMAttribute PA);
LLVMAttribute LLVMGetFunctionAttr(LLVMValueRef Fn);
void LLVMRemoveFunctionAttr(LLVMValueRef Fn, LLVMAttribute PA);

/* Operations on parameters */
uint LLVMCountParams(LLVMValueRef Fn);
void LLVMGetParams(LLVMValueRef Fn, LLVMValueRef* Params);
LLVMValueRef LLVMGetParam(LLVMValueRef Fn, uint Index);
LLVMValueRef LLVMGetParamParent(LLVMValueRef Inst);
LLVMValueRef LLVMGetFirstParam(LLVMValueRef Fn);
LLVMValueRef LLVMGetLastParam(LLVMValueRef Fn);
LLVMValueRef LLVMGetNextParam(LLVMValueRef Arg);
LLVMValueRef LLVMGetPreviousParam(LLVMValueRef Arg);
void LLVMAddAttribute(LLVMValueRef Arg, LLVMAttribute PA);
void LLVMRemoveAttribute(LLVMValueRef Arg, LLVMAttribute PA);
LLVMAttribute LLVMGetAttribute(LLVMValueRef Arg);
void LLVMSetParamAlignment(LLVMValueRef Arg, uint align_);

/* Operations on basic blocks */
LLVMValueRef LLVMBasicBlockAsValue(LLVMBasicBlockRef BB);
LLVMBool LLVMValueIsBasicBlock(LLVMValueRef Val);
LLVMBasicBlockRef LLVMValueAsBasicBlock(LLVMValueRef Val);
LLVMValueRef LLVMGetBasicBlockParent(LLVMBasicBlockRef BB);
LLVMValueRef LLVMGetBasicBlockTerminator(LLVMBasicBlockRef BB);
uint LLVMCountBasicBlocks(LLVMValueRef Fn);
void LLVMGetBasicBlocks(LLVMValueRef Fn, LLVMBasicBlockRef* BasicBlocks);
LLVMBasicBlockRef LLVMGetFirstBasicBlock(LLVMValueRef Fn);
LLVMBasicBlockRef LLVMGetLastBasicBlock(LLVMValueRef Fn);
LLVMBasicBlockRef LLVMGetNextBasicBlock(LLVMBasicBlockRef BB);
LLVMBasicBlockRef LLVMGetPreviousBasicBlock(LLVMBasicBlockRef BB);
LLVMBasicBlockRef LLVMGetEntryBasicBlock(LLVMValueRef Fn);

LLVMBasicBlockRef LLVMAppendBasicBlockInContext(LLVMContextRef C,
                                                LLVMValueRef Fn,
                                                /*const*/ const(char)* Name);
LLVMBasicBlockRef LLVMInsertBasicBlockInContext(LLVMContextRef C,
                                                LLVMBasicBlockRef BB,
                                                /*const*/ const(char)* Name);

LLVMBasicBlockRef LLVMAppendBasicBlock(LLVMValueRef Fn, /*const*/ const(char)* Name);
LLVMBasicBlockRef LLVMInsertBasicBlock(LLVMBasicBlockRef InsertBeforeBB,
                                       /*const*/ const(char)* Name);
void LLVMDeleteBasicBlock(LLVMBasicBlockRef BB);
void LLVMRemoveBasicBlockFromParent(LLVMBasicBlockRef BB);

void LLVMMoveBasicBlockBefore(LLVMBasicBlockRef BB, LLVMBasicBlockRef MovePos);
void LLVMMoveBasicBlockAfter(LLVMBasicBlockRef BB, LLVMBasicBlockRef MovePos);

LLVMValueRef LLVMGetFirstInstruction(LLVMBasicBlockRef BB);
LLVMValueRef LLVMGetLastInstruction(LLVMBasicBlockRef BB);

/* Operations on instructions */
LLVMBasicBlockRef LLVMGetInstructionParent(LLVMValueRef Inst);
LLVMValueRef LLVMGetNextInstruction(LLVMValueRef Inst);
LLVMValueRef LLVMGetPreviousInstruction(LLVMValueRef Inst);
void LLVMInstructionEraseFromParent(LLVMValueRef Inst);
LLVMOpcode   LLVMGetInstructionOpcode(LLVMValueRef Inst);
LLVMIntPredicate LLVMGetICmpPredicate(LLVMValueRef Inst);

/* Operations on call sites */
void LLVMSetInstructionCallConv(LLVMValueRef Instr, uint CC);
uint LLVMGetInstructionCallConv(LLVMValueRef Instr);
void LLVMAddInstrAttribute(LLVMValueRef Instr, uint index, LLVMAttribute);
void LLVMRemoveInstrAttribute(LLVMValueRef Instr, uint index,
                              LLVMAttribute);
void LLVMSetInstrParamAlignment(LLVMValueRef Instr, uint index,
                                uint align_);

/* Operations on call instructions (only) */
LLVMBool LLVMIsTailCall(LLVMValueRef CallInst);
void LLVMSetTailCall(LLVMValueRef CallInst, LLVMBool IsTailCall);

/* Operations on switch instructions (only) */
LLVMBasicBlockRef LLVMGetSwitchDefaultDest(LLVMValueRef SwitchInstr);

/* Operations on phi nodes */
void LLVMAddIncoming(LLVMValueRef PhiNode, LLVMValueRef* IncomingValues,
                     LLVMBasicBlockRef* IncomingBlocks, uint Count);
uint LLVMCountIncoming(LLVMValueRef PhiNode);
LLVMValueRef LLVMGetIncomingValue(LLVMValueRef PhiNode, uint Index);
LLVMBasicBlockRef LLVMGetIncomingBlock(LLVMValueRef PhiNode, uint Index);

/*===-- Instruction builders ----------------------------------------------===*/

/* An instruction builder represents a point within a basic block, and is the
 * exclusive means of building instructions using the C interface.
 */

LLVMBuilderRef LLVMCreateBuilderInContext(LLVMContextRef C);
LLVMBuilderRef LLVMCreateBuilder();
void LLVMPositionBuilder(LLVMBuilderRef Builder, LLVMBasicBlockRef Block,
                         LLVMValueRef Instr);
void LLVMPositionBuilderBefore(LLVMBuilderRef Builder, LLVMValueRef Instr);
void LLVMPositionBuilderAtEnd(LLVMBuilderRef Builder, LLVMBasicBlockRef Block);
LLVMBasicBlockRef LLVMGetInsertBlock(LLVMBuilderRef Builder);
void LLVMClearInsertionPosition(LLVMBuilderRef Builder);
void LLVMInsertIntoBuilder(LLVMBuilderRef Builder, LLVMValueRef Instr);
void LLVMInsertIntoBuilderWithName(LLVMBuilderRef Builder, LLVMValueRef Instr,
                                   /*const*/ const(char)* Name);
void LLVMDisposeBuilder(LLVMBuilderRef Builder);

/* Metadata */
void LLVMSetCurrentDebugLocation(LLVMBuilderRef Builder, LLVMValueRef L);
LLVMValueRef LLVMGetCurrentDebugLocation(LLVMBuilderRef Builder);
void LLVMSetInstDebugLocation(LLVMBuilderRef Builder, LLVMValueRef Inst);

/* Terminators */
LLVMValueRef LLVMBuildRetVoid(LLVMBuilderRef);
LLVMValueRef LLVMBuildRet(LLVMBuilderRef, LLVMValueRef V);
LLVMValueRef LLVMBuildAggregateRet(LLVMBuilderRef, LLVMValueRef* RetVals,
                                   uint N);
LLVMValueRef LLVMBuildBr(LLVMBuilderRef, LLVMBasicBlockRef Dest);
LLVMValueRef LLVMBuildCondBr(LLVMBuilderRef, LLVMValueRef If,
                             LLVMBasicBlockRef Then, LLVMBasicBlockRef Else);
LLVMValueRef LLVMBuildSwitch(LLVMBuilderRef, LLVMValueRef V,
                             LLVMBasicBlockRef Else, uint NumCases);
LLVMValueRef LLVMBuildIndirectBr(LLVMBuilderRef B, LLVMValueRef Addr,
                                 uint NumDests);
LLVMValueRef LLVMBuildInvoke(LLVMBuilderRef, LLVMValueRef Fn,
                             LLVMValueRef* Args, uint NumArgs,
                             LLVMBasicBlockRef Then, LLVMBasicBlockRef Catch,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildLandingPad(LLVMBuilderRef B, LLVMTypeRef Ty,
                                 LLVMValueRef PersFn, uint NumClauses,
                                 /*const*/ char *Name);
LLVMValueRef LLVMBuildResume(LLVMBuilderRef B, LLVMValueRef Exn);
LLVMValueRef LLVMBuildUnreachable(LLVMBuilderRef);

/* Add a case to the switch instruction */
void LLVMAddCase(LLVMValueRef Switch, LLVMValueRef OnVal,
                 LLVMBasicBlockRef Dest);

/* Add a destination to the indirectbr instruction */
void LLVMAddDestination(LLVMValueRef IndirectBr, LLVMBasicBlockRef Dest);

/* Add a catch or filter clause to the landingpad instruction */
void LLVMAddClause(LLVMValueRef LandingPad, LLVMValueRef ClauseVal);

/* Set the 'cleanup' flag in the landingpad instruction */
void LLVMSetCleanup(LLVMValueRef LandingPad, LLVMBool Val);

/* Arithmetic */
LLVMValueRef LLVMBuildAdd(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                          /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildNSWAdd(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildNUWAdd(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFAdd(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildSub(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                          /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildNSWSub(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildNUWSub(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFSub(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildMul(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                          /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildNSWMul(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildNUWMul(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFMul(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildUDiv(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildSDiv(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildExactSDiv(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                                /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFDiv(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildURem(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildSRem(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFRem(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildShl(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildLShr(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildAShr(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildAnd(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                          /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildOr(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                          /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildXor(LLVMBuilderRef, LLVMValueRef LHS, LLVMValueRef RHS,
                          /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildBinOp(LLVMBuilderRef B, LLVMOpcode Op,
                            LLVMValueRef LHS, LLVMValueRef RHS,
                            /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildNeg(LLVMBuilderRef, LLVMValueRef V, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildNSWNeg(LLVMBuilderRef B, LLVMValueRef V,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildNUWNeg(LLVMBuilderRef B, LLVMValueRef V,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFNeg(LLVMBuilderRef, LLVMValueRef V, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildNot(LLVMBuilderRef, LLVMValueRef V, /*const*/ const(char)* Name);

/* Memory */
LLVMValueRef LLVMBuildMalloc(LLVMBuilderRef, LLVMTypeRef Ty, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildArrayMalloc(LLVMBuilderRef, LLVMTypeRef Ty,
                                  LLVMValueRef Val, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildAlloca(LLVMBuilderRef, LLVMTypeRef Ty, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildArrayAlloca(LLVMBuilderRef, LLVMTypeRef Ty,
                                  LLVMValueRef Val, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFree(LLVMBuilderRef, LLVMValueRef PointerVal);
LLVMValueRef LLVMBuildLoad(LLVMBuilderRef, LLVMValueRef PointerVal,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildStore(LLVMBuilderRef, LLVMValueRef Val, LLVMValueRef Ptr);
LLVMValueRef LLVMBuildGEP(LLVMBuilderRef B, LLVMValueRef Pointer,
                          LLVMValueRef* Indices, uint NumIndices,
                          /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildInBoundsGEP(LLVMBuilderRef B, LLVMValueRef Pointer,
                                  LLVMValueRef* Indices, uint NumIndices,
                                  /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildStructGEP(LLVMBuilderRef B, LLVMValueRef Pointer,
                                uint Idx, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildGlobalString(LLVMBuilderRef B, /*const*/ const(char)* Str,
                                   /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildGlobalStringPtr(LLVMBuilderRef B, /*const*/ const(char)* Str,
                                      /*const*/ const(char)* Name);

/* Casts */
LLVMValueRef LLVMBuildTrunc(LLVMBuilderRef, LLVMValueRef Val,
                            LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildZExt(LLVMBuilderRef, LLVMValueRef Val,
                           LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildSExt(LLVMBuilderRef, LLVMValueRef Val,
                           LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFPToUI(LLVMBuilderRef, LLVMValueRef Val,
                             LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFPToSI(LLVMBuilderRef, LLVMValueRef Val,
                             LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildUIToFP(LLVMBuilderRef, LLVMValueRef Val,
                             LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildSIToFP(LLVMBuilderRef, LLVMValueRef Val,
                             LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFPTrunc(LLVMBuilderRef, LLVMValueRef Val,
                              LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFPExt(LLVMBuilderRef, LLVMValueRef Val,
                            LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildPtrToInt(LLVMBuilderRef, LLVMValueRef Val,
                               LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildIntToPtr(LLVMBuilderRef, LLVMValueRef Val,
                               LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildBitCast(LLVMBuilderRef, LLVMValueRef Val,
                              LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildZExtOrBitCast(LLVMBuilderRef, LLVMValueRef Val,
                                    LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildSExtOrBitCast(LLVMBuilderRef, LLVMValueRef Val,
                                    LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildTruncOrBitCast(LLVMBuilderRef, LLVMValueRef Val,
                                     LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildCast(LLVMBuilderRef B, LLVMOpcode Op, LLVMValueRef Val,
                           LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildPointerCast(LLVMBuilderRef, LLVMValueRef Val,
                                  LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildIntCast(LLVMBuilderRef, LLVMValueRef Val, /*Signed cast!*/
                              LLVMTypeRef DestTy, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFPCast(LLVMBuilderRef, LLVMValueRef Val,
                             LLVMTypeRef DestTy, /*const*/ const(char)* Name);

/* Comparisons */
LLVMValueRef LLVMBuildICmp(LLVMBuilderRef, LLVMIntPredicate Op,
                           LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildFCmp(LLVMBuilderRef, LLVMRealPredicate Op,
                           LLVMValueRef LHS, LLVMValueRef RHS,
                           /*const*/ const(char)* Name);

/* Miscellaneous instructions */
LLVMValueRef LLVMBuildPhi(LLVMBuilderRef, LLVMTypeRef Ty, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildCall(LLVMBuilderRef, LLVMValueRef Fn,
                           LLVMValueRef* Args, uint NumArgs,
                           /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildSelect(LLVMBuilderRef, LLVMValueRef If,
                             LLVMValueRef Then, LLVMValueRef Else,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildVAArg(LLVMBuilderRef, LLVMValueRef List, LLVMTypeRef Ty,
                            /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildExtractElement(LLVMBuilderRef, LLVMValueRef VecVal,
                                     LLVMValueRef Index, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildInsertElement(LLVMBuilderRef, LLVMValueRef VecVal,
                                    LLVMValueRef EltVal, LLVMValueRef Index,
                                    /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildShuffleVector(LLVMBuilderRef, LLVMValueRef V1,
                                    LLVMValueRef V2, LLVMValueRef Mask,
                                    /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildExtractValue(LLVMBuilderRef, LLVMValueRef AggVal,
                                   uint Index, /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildInsertValue(LLVMBuilderRef, LLVMValueRef AggVal,
                                  LLVMValueRef EltVal, uint Index,
                                  /*const*/ const(char)* Name);

LLVMValueRef LLVMBuildIsNull(LLVMBuilderRef, LLVMValueRef Val,
                             /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildIsNotNull(LLVMBuilderRef, LLVMValueRef Val,
                                /*const*/ const(char)* Name);
LLVMValueRef LLVMBuildPtrDiff(LLVMBuilderRef, LLVMValueRef LHS,
                              LLVMValueRef RHS, /*const*/ const(char)* Name);


/*===-- Module providers --------------------------------------------------===*/

/* Changes the type of M so it can be passed to FunctionPassManagers and the
 * JIT.  They take ModuleProviders for historical reasons.
 */
LLVMModuleProviderRef
LLVMCreateModuleProviderForExistingModule(LLVMModuleRef M);

/* Destroys the module M.
 */
void LLVMDisposeModuleProvider(LLVMModuleProviderRef M);


/*===-- Memory buffers ----------------------------------------------------===*/

LLVMBool LLVMCreateMemoryBufferWithContentsOfFile(/*const*/ const(char)* Path,
                                                  LLVMMemoryBufferRef* OutMemBuf,
                                                  char** OutMessage);
LLVMBool LLVMCreateMemoryBufferWithSTDIN(LLVMMemoryBufferRef* OutMemBuf,
                                         char** OutMessage);
void LLVMDisposeMemoryBuffer(LLVMMemoryBufferRef MemBuf);

/*===-- Pass Registry -----------------------------------------------------===*/

/** Return the global pass registry, for use with initialization functions.
    See llvm::PassRegistry::getPassRegistry. */
LLVMPassRegistryRef LLVMGetGlobalPassRegistry();

/*===-- Pass Managers -----------------------------------------------------===*/

/** Constructs a new whole-module pass pipeline. This type of pipeline is
    suitable for link-time optimization and whole-module transformations.
    See llvm::PassManager::PassManager. */
LLVMPassManagerRef LLVMCreatePassManager();

/** Constructs a new function-by-function pass pipeline over the module
    provider. It does not take ownership of the module provider. This type of
    pipeline is suitable for code generation and JIT compilation tasks.
    See llvm::FunctionPassManager::FunctionPassManager. */
LLVMPassManagerRef LLVMCreateFunctionPassManagerForModule(LLVMModuleRef M);

/** Deprecated: Use LLVMCreateFunctionPassManagerForModule instead. */
LLVMPassManagerRef LLVMCreateFunctionPassManager(LLVMModuleProviderRef MP);

/** Initializes, executes on the provided module, and finalizes all of the
    passes scheduled in the pass manager. Returns 1 if any of the passes
    modified the module, 0 otherwise. See llvm::PassManager::run(Module&). */
LLVMBool LLVMRunPassManager(LLVMPassManagerRef PM, LLVMModuleRef M);

/** Initializes all of the function passes scheduled in the function pass
    manager. Returns 1 if any of the passes modified the module, 0 otherwise.
    See llvm::FunctionPassManager::doInitialization. */
LLVMBool LLVMInitializeFunctionPassManager(LLVMPassManagerRef FPM);

/** Executes all of the function passes scheduled in the function pass manager
    on the provided function. Returns 1 if any of the passes modified the
    function, false otherwise.
    See llvm::FunctionPassManager::run(Function&). */
LLVMBool LLVMRunFunctionPassManager(LLVMPassManagerRef FPM, LLVMValueRef F);

/** Finalizes all of the function passes scheduled in in the function pass
    manager. Returns 1 if any of the passes modified the module, 0 otherwise.
    See llvm::FunctionPassManager::doFinalization. */
LLVMBool LLVMFinalizeFunctionPassManager(LLVMPassManagerRef FPM);

/** Frees the memory of a pass pipeline. For function pipelines, does not free
    the module provider.
    See llvm::PassManagerBase::~PassManagerBase. */
void LLVMDisposePassManager(LLVMPassManagerRef PM);
