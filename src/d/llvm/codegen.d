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

/**
 * FIXME: This part of the backend's structure is wrong.
 *        Most of the CodeGen related state is in GlobalGen,
 *        When it should be in there. In turn, GlobalGen should contain
 *        no state such as it can be insteaciate on the fly using a Codegen
 *        object.
 *        In turn, other parts of the backend, such as LocalGen should
 *        reference CodeGen instead of GlobalGen.
 *        In addition, the LLVMBackend object should not pre-instanciate
 *        a GlobalGen object as this can now be done lazily.
 */
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

	import d.llvm.global;
	GlobalData globalData;

	import d.llvm.local;
	LocalData localData;

	import d.llvm.constant;
	ConstantData constantData;

	import d.llvm.runtime;
	RuntimeData runtimeData;

	import d.llvm.statement;
	StatementGenData statementGenData;

	import d.llvm.intrinsic;
	IntrinsicGenData intrinsicGenData;

	LLVMValueRef unlikelyBranch;
	uint profKindID;

	LLVMAttributeRef noReturn;
	LLVMAttributeRef noAlias;
	LLVMAttributeRef noUnwind;
	LLVMAttributeRef framePointer;

	import d.llvm.debuginfo;
	DebugInfoData debugInfoData;

	import d.semantic.semantic;
	this(SemanticPass sema, Module main, LLVMTargetMachineRef targetMachine,
	     bool debugBuild) {
		this.context = sema.context;
		this.scheduler = sema.scheduler;
		this.object = sema.object;

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

		auto floc = main.location.getFullLocation(context);
		auto dloc = floc.start.getDebugLocation();
		auto name = dloc.filename.toStringz(context);
		dmodule = LLVMModuleCreateWithNameInContext(name, llvmCtx);
		LLVMSetIsNewDbgInfoFormat(dmodule, true);

		targetData = LLVMCreateTargetDataLayout(targetMachine);
		LLVMSetModuleDataLayout(dmodule, targetData);

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

		if (debugBuild) {
			debugInfoData.create(dmodule, context, dloc);
		}
	}

	~this() {
		debugInfoData.dispose();

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
