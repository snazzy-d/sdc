module d.llvm.codegen;

import d.ir.expression;
import d.ir.statement;
import d.ir.symbol;
import d.ir.type;

import d.llvm.expression;
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
	private ExpressionGen expressionGen;
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
	
	size_t breakUnwindBlock;
	size_t continueUnwindBlock;
	
	LLVMValueRef unlikelyBranch;
	uint profKindID;
	
	this(Context context, string name) {
		this.context	= context;
		
		symbolGen		= new SymbolGen(this);
		expressionGen	= new ExpressionGen(this);
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
	
	auto visit(ValueSymbol s) {
		return symbolGen.visit(s);
	}
	
	auto visit(TypeSymbol s) {
		return symbolGen.visit(s);
	}
	
	auto getNewInit(TypeSymbol s) {
		return typeGen.getNewInit(s);
	}
	
	auto getTypeInfo(TypeSymbol s) {
		return typeGen.getTypeInfo(s);
	}
	
	auto visit(Expression e) {
		return expressionGen.visit(e);
	}
	
	auto visit(QualType t) {
		return typeGen.visit(t);
	}
	
	auto visit(Type t) {
		return typeGen.visit(t);
	}
	
	auto buildClassType(Class c) {
		return typeGen.buildClass(c);
	}
	
	auto buildCall(LLVMValueRef callee, LLVMValueRef[] args) {
		return expressionGen.buildCall(callee, args);
	}
	
	auto buildDString(string str) {
		return stringGen.buildDString(str);
	}
	
	auto ctfe(Expression e, LLVMExecutionEngineRef executionEngine) {
		scope(failure) LLVMDumpModule(dmodule);
		
		auto funType = LLVMFunctionType(visit(e.type), null, 0, false);
		
		auto fun = LLVMAddFunction(dmodule, "__ctfe", funType);
		scope(exit) LLVMDeleteFunction(fun);
		
		auto backupCurrentBB = LLVMGetInsertBlock(builder);
		scope(exit) {
			if(backupCurrentBB) {
				LLVMPositionBuilderAtEnd(builder, backupCurrentBB);
			} else {
				LLVMClearInsertionPosition(builder);
			}
		}
		
		auto bodyBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "");
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		
		// Generate function's body.
		LLVMBuildRet(builder, visit(e));
		
		checkModule();
		
		auto result = LLVMRunFunction(executionEngine, fun, 0, null);
		scope(exit) LLVMDisposeGenericValue(result);
		
		return LLVMGenericValueToInt(result, true);
	}
	
	auto ctString(Expression e, LLVMExecutionEngineRef executionEngine) in {
		assert(cast(SliceType) peelAlias(e.type).type, "this only CTFE strings.");
	} body {
		scope(failure) LLVMDumpModule(dmodule);
		
		// Create a global variable that recieve the string.
		auto reciever = LLVMAddGlobal(dmodule, visit(e.type), "__ctString");
		scope(exit) LLVMDeleteGlobal(reciever);
		
		auto funType = LLVMFunctionType(LLVMVoidTypeInContext(llvmCtx), null, 0, false);
		
		auto fun = LLVMAddFunction(dmodule, "__ctfe", funType);
		scope(exit) LLVMDeleteFunction(fun);
		
		auto backupCurrentBB = LLVMGetInsertBlock(builder);
		scope(exit) {
			if(backupCurrentBB) {
				LLVMPositionBuilderAtEnd(builder, backupCurrentBB);
			} else {
				LLVMClearInsertionPosition(builder);
			}
		}
		
		auto bodyBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "");
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		
		// Generate function's body.
		LLVMBuildStore(builder, visit(e), reciever);
		LLVMBuildRetVoid(builder);
		
		checkModule();
		
		string s;
		LLVMAddGlobalMapping(executionEngine, reciever, &s);
		LLVMRunFunction(executionEngine, fun, 0, null);
		
		return s.idup;
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
		// TODO: LLVMGetNamedFunction
		return cache.get(name, cache[name] = {
			return LLVMAddFunction(pass.dmodule, name.toStringz(), type);
		}());
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
		return getNamedFunction("_d_array_bounds", LLVMFunctionType(LLVMVoidTypeInContext(llvmCtx), [LLVMStructTypeInContext(llvmCtx, [LLVMInt64TypeInContext(llvmCtx), LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0)].ptr, 2, false), LLVMInt32TypeInContext(llvmCtx)].ptr, 2, false));
	}
	
	auto getAllocMemory() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoAlias);
		return getNamedFunction("_d_allocmemory", LLVMFunctionType(LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0), [LLVMInt64TypeInContext(llvmCtx)].ptr, 1, false));
	}
	
	auto getEhTypeidFor() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoAlias);
		return getNamedFunction("llvm.eh.typeid.for", LLVMFunctionType(LLVMInt32TypeInContext(llvmCtx), [LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0)].ptr, 1, false));
	}
}

