module d.llvm.codegen;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;
import llvm.c.target;
import llvm.c.targetMachine;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

final class CodeGen {
	import source.context;
	Context context;

	import d.semantic.scheduler;
	Scheduler scheduler;

	import d.object;
	ObjectReference object;

	LLVMContextRef llvmCtx;
	LLVMModuleRef dmodule;

	LLVMTypeRef llvmPtr;
	LLVMTypeRef llvmSlice;
	LLVMValueRef llvmNull;
	LLVMTypeRef llvmVoid;

	LLVMTypeRef i1;
	LLVMTypeRef i8;
	LLVMTypeRef i16;
	LLVMTypeRef i32;
	LLVMTypeRef i64;
	LLVMTypeRef i128;

	LLVMTargetDataRef targetData;

	import d.llvm.type;
	TypeGenData typeGenData;

	LLVMValueRef unlikelyBranch;
	uint profKindID;

	LLVMAttributeRef noReturn;
	LLVMAttributeRef noAlias;
	LLVMAttributeRef noUnwind;
	LLVMAttributeRef framePointer;

	// FIXME: We hold a refernece to the backend here so it is not GCed.
	// Now that JIT use its own codegen, no reference to the JIT backend
	// is held if that one goes. The whole thing needs to be refactored
	// in a way that is more sensible.
	import d.llvm.backend;
	LLVMBackend backend;

	import d.semantic.semantic;
	this(SemanticPass sema, string name, LLVMBackend backend,
	     LLVMTargetMachineRef targetMachine) {
		this.context = sema.context;
		this.scheduler = sema.scheduler;
		this.object = sema.object;
		this.backend = backend;

		llvmCtx = LLVMContextCreate();

		llvmPtr = LLVMPointerTypeInContext(llvmCtx, 0);
		llvmNull = LLVMConstNull(llvmPtr);
		llvmVoid = LLVMVoidTypeInContext(llvmCtx);

		i1 = LLVMInt1TypeInContext(llvmCtx);
		i8 = LLVMInt8TypeInContext(llvmCtx);
		i16 = LLVMInt16TypeInContext(llvmCtx);
		i32 = LLVMInt32TypeInContext(llvmCtx);
		i64 = LLVMInt64TypeInContext(llvmCtx);
		i128 = LLVMInt128TypeInContext(llvmCtx);

		LLVMTypeRef[2] sliceElements = [i64, llvmPtr];
		llvmSlice = LLVMStructTypeInContext(llvmCtx, sliceElements.ptr,
		                                    sliceElements.length, false);

		import std.string;
		dmodule = LLVMModuleCreateWithNameInContext(name.toStringz(), llvmCtx);

		this.targetData = LLVMCreateTargetDataLayout(targetMachine);
		LLVMSetModuleDataLayout(dmodule, this.targetData);

		const branch_weights = "branch_weights";
		LLVMValueRef[3] branch_metadata = [
			LLVMMDStringInContext(llvmCtx, branch_weights.ptr,
			                      branch_weights.length),
			LLVMConstInt(i32, 2000, false), LLVMConstInt(i32, 0, false)];

		unlikelyBranch = LLVMMDNodeInContext(llvmCtx, branch_metadata.ptr,
		                                     branch_metadata.length);

		const prof = "prof";
		profKindID = LLVMGetMDKindIDInContext(llvmCtx, prof.ptr, prof.length);

		noReturn = getAttribute("noreturn");
		noAlias = getAttribute("noalias");
		noUnwind = getAttribute("nounwind");
		framePointer = getAttribute("frame-pointer", "non-leaf");
	}

	~this() {
		LLVMDisposeModule(dmodule);
		LLVMDisposeTargetData(targetData);
		LLVMContextDispose(llvmCtx);
	}

	auto getAttribute(string name, ulong value = 0) {
		auto id = LLVMGetEnumAttributeKindForName(name.ptr, name.length);
		return LLVMCreateEnumAttribute(llvmCtx, id, value);
	}

	auto getAttribute(string name, string value)
			in(name.length < uint.max, "Name is too long!")
			in(value.length < uint.max, "Value is too long!") {
		return LLVMCreateStringAttribute(
			llvmCtx, name.ptr, cast(uint) name.length, value.ptr,
			cast(uint) value.length);
	}
}
