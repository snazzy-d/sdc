module d.llvm.codegen;

import d.ast.declaration;
import d.ast.dmodule;
import d.ast.statement;
import d.ast.expression;
import d.ast.type;

import d.llvm.declaration;
import d.llvm.statement;
import d.llvm.expression;
import d.llvm.string;
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
	private DeclarationGen declarationGen;
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
	
	bool isSigned;
	
	this(string name) {
		declarationGen	= new DeclarationGen(this);
		statementGen	= new StatementGen(this);
		expressionGen	= new ExpressionGen(this);
		addressOfGen	= new AddressOfGen(this);
		typeGen			= new TypeGen(this);
		
		stringGen		= new StringGen(this);
		
		druntimeGen		= new DruntimeGen(this);
		
		context = LLVMContextCreate();
		builder = LLVMCreateBuilderInContext(context);
		dmodule = LLVMModuleCreateWithNameInContext(name.toStringz(), context);
	}
	
	LLVMModuleRef visit(Module[] modules) {
		// Dump module content on failure (for debug purpose).
		scope(failure) LLVMDumpModule(dmodule);
		
		foreach(m; modules) {
			visit(m);
		}
		
		checkModule();
		
		return dmodule;
	}
	
	Module visit(Module m) {
		foreach(decl; m.declarations) {
			visit(decl);
		}
		
		return m;
	}
	
	auto visit(Declaration decl) {
		return declarationGen.visit(decl);
	}
	
	auto visit(ExpressionSymbol s) {
		return declarationGen.visit(s);
	}
	
	auto visit(TypeSymbol s) {
		return declarationGen.visit(s);
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
		
		auto bodyBB = LLVMAppendBasicBlock(fun, "");
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		
		// Generate function's body.
		LLVMBuildRet(builder, visit(e));
		
		checkModule();
		
		return LLVMRunFunction(executionEngine, fun, 0, null);
	}
	
	auto ctString(Expression e, LLVMExecutionEngineRef executionEngine) in {
		assert(cast(SliceType) e.type, "this only CTFE strings.");
	} body {
		scope(failure) LLVMDumpModule(dmodule);
		
		auto funType = LLVMFunctionType(LLVMVoidTypeInContext(context), null, 0, false);
		
		auto fun = LLVMAddFunction(dmodule, "__ctfe", funType);
		scope(exit) LLVMDeleteFunction(fun);
		
		auto bodyBB = LLVMAppendBasicBlock(fun, "");
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		
		// Create a global variable that recieve the string.
		auto reciever = LLVMAddGlobal(dmodule, visit(e.type), "__ctString".ptr);
		scope(exit) LLVMDeleteGlobal(reciever);
		
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

class DruntimeGen {
	private CodeGenPass pass;
	alias pass this;
	
	private LLVMValueRef[string] cache;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
final:
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
	
	auto getArrayBound() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoReturn);
		return getNamedFunction("_d_array_bounds", LLVMFunctionType(LLVMVoidTypeInContext(context), [LLVMStructTypeInContext(context, [LLVMInt64TypeInContext(context), LLVMPointerType(LLVMInt8TypeInContext(context), 0)].ptr, 2, false), LLVMInt32TypeInContext(context)].ptr, 2, false));
	}
}

