module d.llvm.codegen;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;
import llvm.c.target;

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

	LLVMValueRef[ValueSymbol] globals;

	import d.llvm.local;
	LocalData localData;

	LLVMTargetDataRef targetData;

	import d.llvm.type;
	TypeGenData typeGenData;

	import d.llvm.runtime;
	RuntimeData runtimeData;

	private LLVMValueRef[string] stringLiterals;

	import d.llvm.statement;
	StatementGenData statementGenData;

	import d.llvm.intrinsic;
	IntrinsicGenData intrinsicGenData;

	LLVMValueRef unlikelyBranch;
	uint profKindID;

	// FIXME: We hold a refernece to the backend here so it is not GCed.
	// Now that JIT use its own codegen, no reference to the JIT backend
	// is held if that one goes. The whole thing needs to be refactored
	// in a way that is more sensible.
	import d.llvm.backend;
	LLVMBackend backend;

	import d.semantic.semantic;
	this(SemanticPass sema, string name, LLVMBackend backend,
	     LLVMTargetDataRef targetData) {
		this.context = sema.context;
		this.scheduler = sema.scheduler;
		this.object = sema.object;
		this.backend = backend;

		// Make sure globals are initialized.
		globals[null] = null;
		globals.remove(null);

		llvmCtx = LLVMContextCreate();
		LLVMContextSetOpaquePointers(llvmCtx, true);

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

		LLVMSetModuleDataLayout(dmodule, targetData);
		this.targetData = LLVMGetModuleDataLayout(dmodule);

		const branch_weights = "branch_weights";
		LLVMValueRef[3] branch_metadata = [
			LLVMMDStringInContext(llvmCtx, branch_weights.ptr,
			                      branch_weights.length),
			LLVMConstInt(i32, 65536, false), LLVMConstInt(i32, 0, false), ];

		unlikelyBranch = LLVMMDNodeInContext(llvmCtx, branch_metadata.ptr,
		                                     branch_metadata.length);

		const prof = "prof";
		profKindID = LLVMGetMDKindIDInContext(llvmCtx, prof.ptr, prof.length);
	}

	~this() {
		LLVMDisposeModule(dmodule);
		LLVMContextDispose(llvmCtx);
	}

	Module visit(Module m) {
		// Dump module content on failure (for debug purpose).
		scope(failure) LLVMDumpModule(dmodule);

		foreach (s; m.members) {
			import d.llvm.global;
			GlobalGen(this).define(s);
		}

		checkModule();
		return m;
	}

	auto buildCString(string str)
			in(str.length < uint.max, "string length must be < uint.max") {
		auto cstr = str ~ '\0';
		auto charArray = LLVMConstStringInContext(llvmCtx, cstr.ptr,
		                                          cast(uint) cstr.length, true);

		auto type = LLVMTypeOf(charArray);
		auto globalVar = LLVMAddGlobal(dmodule, type, ".str");
		LLVMSetInitializer(globalVar, charArray);
		LLVMSetLinkage(globalVar, LLVMLinkage.Private);
		LLVMSetGlobalConstant(globalVar, true);
		LLVMSetUnnamedAddr(globalVar, true);

		auto zero = LLVMConstInt(i32, 0, true);
		LLVMValueRef[2] indices = [zero, zero];
		return
			LLVMConstInBoundsGEP2(type, globalVar, indices.ptr, indices.length);
	}

	auto buildDString(string str) {
		return stringLiterals.get(str, stringLiterals[str] = {
			LLVMValueRef[2] slice =
				[LLVMConstInt(i64, str.length, false), buildCString(str)];
			return LLVMConstStructInContext(llvmCtx, slice.ptr, slice.length,
			                                false);
		}());
	}

	auto checkModule() {
		char* msg;
		if (!LLVMVerifyModule(dmodule, LLVMVerifierFailureAction.ReturnStatus,
		                      &msg)) {
			return;
		}

		scope(exit) LLVMDisposeMessage(msg);

		import core.stdc.string;
		auto error = msg[0 .. strlen(msg)].idup;

		throw new Exception(error);
	}

	auto getAttribute(string name, ulong val = 0) {
		auto id = LLVMGetEnumAttributeKindForName(name.ptr, name.length);
		return LLVMCreateEnumAttribute(llvmCtx, id, val);
	}
}
