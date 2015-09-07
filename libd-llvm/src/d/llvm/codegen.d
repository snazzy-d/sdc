module d.llvm.codegen;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.llvm.string;
import d.llvm.type;

import d.object;
import d.semantic.scheduler;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;
import llvm.c.target;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

final class CodeGenPass {
	import d.context.context;
	Context context;
	
	private TypeGen typeGen;
	
	private StringGen stringGen;
	
	DruntimeGen druntimeGen;
	
	ObjectReference object;
	Scheduler scheduler;
	
	LLVMTargetDataRef targetData;
	
	LLVMContextRef llvmCtx;
	LLVMModuleRef dmodule;
	
	LLVMValueRef[ValueSymbol] globals;
	
	struct Closure {
		uint[Variable] indices;
		LLVMTypeRef type;
	}
	
	Closure[][TypeSymbol] embededContexts;
	
	LLVMValueRef unlikelyBranch;
	uint profKindID;
	
	this(Context context, string name, LLVMTargetDataRef targetData) {
		this.context	= context;
		this.targetData	= targetData;

		// Make sure globals are initialized.
		globals[null] = null;
		globals.remove(null);
		
		llvmCtx = LLVMContextCreate();
		
		typeGen			= new TypeGen(this);
		
		stringGen		= new StringGen(this);
		
		druntimeGen		= new DruntimeGen(this);
		
		import std.string;
		dmodule = LLVMModuleCreateWithNameInContext(name.toStringz(), llvmCtx);
		
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
			GlobalGen(this).visit(s);
		}
		
		checkModule();
		
		return m;
	}
	
	auto getTypeInfo(TypeSymbol s) {
		return typeGen.getTypeInfo(s);
	}
	
	auto getVtbl(Class c) {
		return typeGen.getVtbl(c);
	}
	
	auto visit(Type t) {
		return typeGen.visit(t);
	}
	
	auto visit(FunctionType t) {
		return typeGen.visit(t);
	}
	
	auto buildStructType(Struct s) {
		return typeGen.visit(s);
	}
	
	auto buildUnionType(Union u) {
		return typeGen.visit(u);
	}
	
	auto buildClassType(Class c) {
		return typeGen.visit(c);
	}

	auto buildInterfaceType(Interface i) {
		return typeGen.visit(i);
	}

	auto buildEnumType(Enum e) {
		return typeGen.visit(e);
	}
	
	auto buildContextType(Function f) {
		return typeGen.visit(f);
	}
	
	auto buildDString(string str) {
		return stringGen.buildDString(str);
	}
	
	auto checkModule() {
		char* msg;
		if(LLVMVerifyModule(dmodule, LLVMVerifierFailureAction.ReturnStatus, &msg)) {
			scope(exit) LLVMDisposeMessage(msg);
			
			import std.c.string;
			auto error = msg[0 .. strlen(msg)].idup;
			
			throw new Exception(error);
		}
	}
}

final class DruntimeGen {
	private CodeGenPass pass;
	alias pass this;
	
	private LLVMValueRef[string] cache;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	private auto getNamedFunction(string name, lazy LLVMTypeRef type) {
		return cache.get(name, cache[name] = {
			import std.string;
			return LLVMAddFunction(pass.dmodule, name.toStringz(), type);
		}());
	}
	
	private auto getNamedFunction(string name, LLVMValueRef function(CodeGenPass) build) {
		return cache.get(name, cache[name] = build(pass));
	}
	
	auto getAssert() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoReturn);
		return getNamedFunction("_d_assert", LLVMFunctionType(LLVMVoidTypeInContext(llvmCtx), [LLVMStructTypeInContext(llvmCtx, [LLVMInt64TypeInContext(llvmCtx), LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0)].ptr, 2, false), LLVMInt32TypeInContext(llvmCtx)].ptr, 2, false));
	}
	
	auto getAssertMessage() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoReturn);
		return getNamedFunction("_d_assert_msg", LLVMFunctionType(LLVMVoidTypeInContext(llvmCtx), [LLVMStructTypeInContext(llvmCtx, [LLVMInt64TypeInContext(llvmCtx), LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0)].ptr, 2, false), LLVMStructTypeInContext(llvmCtx, [LLVMInt64TypeInContext(llvmCtx), LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0)].ptr, 2, false), LLVMInt32TypeInContext(llvmCtx)].ptr, 3, false));
	}
	
	auto getArrayBound() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoReturn);
		return getNamedFunction("_d_arraybounds", LLVMFunctionType(LLVMVoidTypeInContext(llvmCtx), [LLVMStructTypeInContext(llvmCtx, [LLVMInt64TypeInContext(llvmCtx), LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0)].ptr, 2, false), LLVMInt32TypeInContext(llvmCtx)].ptr, 2, false));
	}
	
	auto getAllocMemory() {
		return getNamedFunction("_d_allocmemory", (p) {
			auto arg = LLVMInt64TypeInContext(p.llvmCtx);
			auto type = LLVMFunctionType(LLVMPointerType(LLVMInt8TypeInContext(p.llvmCtx), 0), &arg, 1, false);
			auto fun = LLVMAddFunction(p.dmodule, "_d_allocmemory", type);
			
			// Trying to get the patch into LLVM
			// LLVMAddReturnAttr(fun, LLVMAttribute.NoAlias);
			return fun;
		});
	}
	
	auto getEhTypeidFor() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoAlias);
		return getNamedFunction("llvm.eh.typeid.for", LLVMFunctionType(LLVMInt32TypeInContext(llvmCtx), [LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0)].ptr, 1, false));
	}
}

