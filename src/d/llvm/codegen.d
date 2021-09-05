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
	
	LLVMValueRef[ValueSymbol] globals;
	
	import d.llvm.local;
	LocalData localData;
	
	LLVMTargetDataRef targetData;
	
	import d.llvm.type;
	TypeGenData typeGenData;
	
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
	this(SemanticPass sema, string name, LLVMBackend backend, LLVMTargetDataRef targetData) {
		this.context   = sema.context;
		this.scheduler = sema.scheduler;
		this.object    = sema.object;
		this.backend   = backend;
		
		// Make sure globals are initialized.
		globals[null] = null;
		globals.remove(null);
		
		llvmCtx = LLVMContextCreate();
		
		import std.string;
		dmodule = LLVMModuleCreateWithNameInContext(name.toStringz(), llvmCtx);
		
		LLVMSetModuleDataLayout(dmodule, targetData);
		this.targetData = LLVMGetModuleDataLayout(dmodule);
		
		LLVMValueRef[3] branch_metadata;
		
		auto id = "branch_weights";
		branch_metadata[0] = LLVMMDStringInContext(llvmCtx, id.ptr, cast(uint) id.length);
		branch_metadata[1] = LLVMConstInt(LLVMInt32TypeInContext(llvmCtx), 65536, false);
		branch_metadata[2] = LLVMConstInt(LLVMInt32TypeInContext(llvmCtx), 0, false);
		
		unlikelyBranch = LLVMMDNodeInContext(llvmCtx, branch_metadata.ptr, cast(uint) branch_metadata.length);
		
		id = "prof";
		profKindID = LLVMGetMDKindIDInContext(llvmCtx, id.ptr, cast(uint) id.length);
	}
	
	~this() {
		LLVMDisposeModule(dmodule);
		LLVMContextDispose(llvmCtx);
	}
	
	Module visit(Module m) {
		// Dump module content on failure (for debug purpose).
		scope(failure) LLVMDumpModule(dmodule);
		
		foreach(s; m.members) {
			import d.llvm.global;
			GlobalGen(this).define(s);
		}
		
		checkModule();
		return m;
	}
	
	auto buildDString(string str) in {
		assert(str.length <= uint.max, "string length must be <= uint.max");
	} do {
		return stringLiterals.get(str, stringLiterals[str] = {
			auto cstr = str ~ '\0';
			auto charArray = LLVMConstStringInContext(llvmCtx, cstr.ptr, cast(uint) cstr.length, true);
			
			auto globalVar = LLVMAddGlobal(dmodule, LLVMTypeOf(charArray), ".str");
			LLVMSetInitializer(globalVar, charArray);
			LLVMSetLinkage(globalVar, LLVMLinkage.Private);
			LLVMSetGlobalConstant(globalVar, true);
			LLVMSetUnnamedAddr(globalVar, true);
			
			auto zero = LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), 0, true);
			LLVMValueRef[2] indices = [zero, zero];
			
			LLVMValueRef[2] slice;
			slice[0] = LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), str.length, false);
			slice[1] = LLVMConstInBoundsGEP(globalVar, indices.ptr, indices.length);
			
			return LLVMConstStructInContext(llvmCtx, slice.ptr, indices.length, false);
		}());
	}
	
	auto checkModule() {
		char* msg;
		if (LLVMVerifyModule(dmodule, LLVMVerifierFailureAction.ReturnStatus, &msg)) {
			scope(exit) LLVMDisposeMessage(msg);
			
			import core.stdc.string;
			auto error = msg[0 .. strlen(msg)].idup;
			
			throw new Exception(error);
		}
	}
	
	auto getAttribute(string name, ulong val = 0) {
		auto id = LLVMGetEnumAttributeKindForName(name.ptr, name.length);
		return LLVMCreateEnumAttribute(llvmCtx, id, val);
	}
}
