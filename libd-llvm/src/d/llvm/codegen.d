module d.llvm.codegen;

import d.ir.expression;
import d.ir.statement;
import d.ir.symbol;
import d.ir.type;

import d.llvm.string;
import d.llvm.symbol;
import d.llvm.type;

import d.context;
import d.location;
import d.object;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;
import llvm.c.executionEngine;

import std.algorithm;
import std.array;
import std.string;

final class CodeGenPass {
	Context context;
	
	private SymbolGen symbolGen;
	private TypeGen typeGen;
	
	private StringGen stringGen;
	
	DruntimeGen druntimeGen;
	
	ObjectReference object;
	
	LLVMContextRef llvmCtx;
	
	LLVMBuilderRef builder;
	LLVMModuleRef dmodule;
	
	LLVMValueRef thisPtr;
	
	LLVMValueRef lpContext;
	LLVMValueRef[] catchClauses;
	
	enum BlockKind {
		Exit,
		Success,
		Failure,
		Catch,
	}
	
	struct Block {
		BlockKind kind;
		Statement statement;
		LLVMBasicBlockRef landingPadBB;
		LLVMBasicBlockRef unwindBB;
	}
	
	Block[] unwindBlocks;
	
	LLVMValueRef unlikelyBranch;
	uint profKindID;
	
	this(Context context, string name) {
		this.context	= context;
		
		symbolGen		= new SymbolGen(this);
		typeGen			= new TypeGen(this);
		
		stringGen		= new StringGen(this);
		
		druntimeGen		= new DruntimeGen(this);
		
		llvmCtx = LLVMContextCreate();
		builder = LLVMCreateBuilderInContext(llvmCtx);
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
	
	Module visit(Module m) {
		// Dump module content on failure (for debug purpose).
		scope(failure) LLVMDumpModule(dmodule);
		
		foreach(decl; m.members) {
			visit(decl);
		}
		
		checkModule();
		
		return m;
	}
	
	auto visit(Symbol s) {
		return symbolGen.visit(s);
	}
	
	auto visit(TypeSymbol s) {
		return symbolGen.visit(s);
	}
	
	auto visit(Variable v) {
		return symbolGen.genCached(v);
	}
	
	auto visit(Function f) {
		return symbolGen.genCached(f);
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
	
	auto buildClassType(Class c) {
		return typeGen.visit(c);
	}
	
	auto buildEnumType(Enum e) {
		return typeGen.visit(e);
	}
	
	auto getContext(Function f) {
		return symbolGen.getContext(f);
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

