module d.llvm.codegen;

import d.ir.expression;
import d.ir.statement;
import d.ir.symbol;
import d.ir.type;

import d.llvm.expression;
import d.llvm.statement;
import d.llvm.string;
import d.llvm.symbol;
import d.llvm.type;

import d.location;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;
import llvm.c.executionEngine;

import std.algorithm;
import std.array;
import std.string;

final class CodeGenPass {
	private SymbolGen symbolGen;
	private StatementGen statementGen;
	private AddressOfGen addressOfGen;
	private ExpressionGen expressionGen;
	private TypeGen typeGen;
	
	private StringGen stringGen;
	
	DruntimeGen druntimeGen;
	
	LLVMContextRef context;
	
	LLVMBuilderRef builder;
	LLVMModuleRef dmodule;
	
	LLVMBasicBlockRef continueBB;
	LLVMBasicBlockRef breakBB;
	
	LLVMBasicBlockRef[string] labels;
	
	LLVMValueRef switchInstr;
	
	LLVMValueRef unlikelyBranch;
	uint profKindID;
	
	this(string name) {
		symbolGen		= new SymbolGen(this);
		statementGen	= new StatementGen(this);
		expressionGen	= new ExpressionGen(this);
		addressOfGen	= new AddressOfGen(this);
		typeGen			= new TypeGen(this);
		
		stringGen		= new StringGen(this);
		
		druntimeGen		= new DruntimeGen(this);
		
		context = LLVMContextCreate();
		builder = LLVMCreateBuilderInContext(context);
		dmodule = LLVMModuleCreateWithNameInContext(name.toStringz(), context);
		
		// Create a dummy function, as LLVM expect to always have something.
		auto funType = LLVMFunctionType(LLVMVoidTypeInContext(context), null, 0, false);
		auto fun = LLVMAddFunction(dmodule, ".dummy", funType);
		auto basicBlock = LLVMAppendBasicBlockInContext(context, fun, "");
		LLVMPositionBuilderAtEnd(builder, basicBlock);
		LLVMBuildRetVoid(builder);
		
		LLVMValueRef[3] branch_metadata;
		
		auto id = "branch_weights";
		branch_metadata[0] = LLVMMDStringInContext(context, id.ptr, cast(uint) id.length);
		branch_metadata[1] = LLVMConstInt(LLVMInt32TypeInContext(context), 65536, false);
		branch_metadata[2] = LLVMConstInt(LLVMInt32TypeInContext(context), 0, false);
		
		unlikelyBranch = LLVMMDNodeInContext(context, branch_metadata.ptr, cast(uint) branch_metadata.length);
		
		id = "prof";
		profKindID = LLVMGetMDKindIDInContext(context, id.ptr, cast(uint) id.length);
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
	
	auto visit(Statement stmt) {
		return statementGen.visit(stmt);
	}
	
	auto visit(Expression e) {
		return expressionGen.visit(e);
	}
	
	auto addressOf(Expression e) {
		return addressOfGen.visit(e);
	}
	
	auto computeIndice(Location location, Type indexedType, LLVMValueRef indexed, LLVMValueRef indice) {
		return addressOfGen.computeIndice(location, indexedType, indexed, indice);
	}
	
	auto visit(QualType t) {
		return typeGen.visit(t);
	}
	
	auto visit(Type t) {
		return typeGen.visit(t);
	}
	
	auto buildDString(string str) {
		return stringGen.buildDString(str);
	}
	
	auto ctfe(Expression e, LLVMExecutionEngineRef executionEngine) {
		scope(failure) LLVMDumpModule(dmodule);
		
		auto funType = LLVMFunctionType(visit(e.type), null, 0, false);
		
		auto fun = LLVMAddFunction(dmodule, "__ctfe", funType);
		scope(exit) LLVMDeleteFunction(fun);
		
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		scope(exit) LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		
		auto bodyBB = LLVMAppendBasicBlockInContext(context, fun, "");
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		
		// Generate function's body.
		LLVMBuildRet(builder, visit(e));
		
		checkModule();
		
		auto result = LLVMRunFunction(executionEngine, fun, 0, null);
		scope(exit) LLVMDisposeGenericValue(result);
		
		return LLVMGenericValueToInt(result, true);
	}
	
	auto ctString(Expression e, LLVMExecutionEngineRef executionEngine) in {
		assert(cast(SliceType) e.type.type, "this only CTFE strings.");
	} body {
		scope(failure) LLVMDumpModule(dmodule);
		
		// Create a global variable that recieve the string.
		auto reciever = LLVMAddGlobal(dmodule, visit(e.type), "__ctString");
		scope(exit) LLVMDeleteGlobal(reciever);
		
		auto funType = LLVMFunctionType(LLVMVoidTypeInContext(context), null, 0, false);
		
		auto fun = LLVMAddFunction(dmodule, "__ctfe", funType);
		scope(exit) LLVMDeleteFunction(fun);
		
		auto backupCurrentBlock = LLVMGetInsertBlock(builder);
		scope(exit) LLVMPositionBuilderAtEnd(builder, backupCurrentBlock);
		
		auto bodyBB = LLVMAppendBasicBlockInContext(context, fun, "");
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
		return getNamedFunction("_d_assert", LLVMFunctionType(LLVMVoidTypeInContext(context), [LLVMStructTypeInContext(context, [LLVMInt64TypeInContext(context), LLVMPointerType(LLVMInt8TypeInContext(context), 0)].ptr, 2, false), LLVMInt32TypeInContext(context)].ptr, 2, false));
	}
	
	auto getAssertMessage() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoReturn);
		return getNamedFunction("_d_assert_msg", LLVMFunctionType(LLVMVoidTypeInContext(context), [LLVMStructTypeInContext(context, [LLVMInt64TypeInContext(context), LLVMPointerType(LLVMInt8TypeInContext(context), 0)].ptr, 2, false), LLVMStructTypeInContext(context, [LLVMInt64TypeInContext(context), LLVMPointerType(LLVMInt8TypeInContext(context), 0)].ptr, 2, false), LLVMInt32TypeInContext(context)].ptr, 3, false));
	}
	
	auto getArrayBound() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoReturn);
		return getNamedFunction("_d_array_bounds", LLVMFunctionType(LLVMVoidTypeInContext(context), [LLVMStructTypeInContext(context, [LLVMInt64TypeInContext(context), LLVMPointerType(LLVMInt8TypeInContext(context), 0)].ptr, 2, false), LLVMInt32TypeInContext(context)].ptr, 2, false));
	}
	
	auto getAllocMemory() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoAlias);
		return getNamedFunction("_d_allocmemory", LLVMFunctionType(LLVMPointerType(LLVMInt8TypeInContext(context), 0), [LLVMInt64TypeInContext(context)].ptr, 1, false));
	}
}

