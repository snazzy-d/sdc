module d.backend.codegen;

import d.ast.dmodule;

import util.visitor;

import llvm.c.analysis;
import llvm.c.core;

import sdc.location;

import std.algorithm;
import std.array;
import std.string;

auto codeGen(Module[] modules) {
	auto cg = new CodeGenPass();
	
	cg.visit(modules);
	
	return cg.dmodule;
}

import d.ast.declaration;
import d.ast.statement;
import d.ast.expression;
import d.ast.type;

import d.backend.declaration;
import d.backend.statement;
import d.backend.expression;
import d.backend.type;

final class CodeGenPass {
	private DeclarationGen declarationGen;
	private StatementGen statementGen;
	private TypeGen typeGen;
	
	ExpressionGen expressionGen;
	AddressOfGen addressOfGen;
	DruntimeGen druntimeGen;
	
	private LLVMContextRef context;
	
	LLVMBuilderRef builder;
	LLVMModuleRef dmodule;
	
	LLVMBasicBlockRef continueBB;
	LLVMBasicBlockRef breakBB;
	
	LLVMBasicBlockRef[string] labels;
	
	LLVMValueRef switchInstr;
	
	bool isSigned;
	
	this() {
		declarationGen	= new DeclarationGen(this);
		statementGen	= new StatementGen(this);
		expressionGen	= new ExpressionGen(this);
		addressOfGen	= new AddressOfGen(this);
		typeGen			= new TypeGen(this);
		
		druntimeGen		= new DruntimeGen(this);
		
		// TODO: types in context.
		context = LLVMContextCreate();
		builder = LLVMCreateBuilderInContext(context);
	}
	
	Module[] visit(Module[] modules) {
		dmodule = LLVMModuleCreateWithNameInContext(modules.back.location.filename.toStringz(), context);
		
		// Dump module content on failure (for debug purpose).
		scope(failure) LLVMDumpModule(dmodule);
		
		return modules.map!(m => visit(m)).array();
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
	
	auto visit(Type t) {
		return typeGen.visit(t);
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
		return getNamedFunction("_d_assert", LLVMFunctionType(LLVMVoidType(), [LLVMStructType([LLVMInt64Type(), LLVMPointerType(LLVMInt8Type(), 0)].ptr, 2, false), LLVMInt32Type()].ptr, 2, false));
	}
	
	auto getArrayBound() {
		// TODO: LLVMAddFunctionAttr(fun, LLVMAttribute.NoReturn);
		return getNamedFunction("_d_array_bounds", LLVMFunctionType(LLVMVoidType(), [LLVMStructType([LLVMInt64Type(), LLVMPointerType(LLVMInt8Type(), 0)].ptr, 2, false), LLVMInt32Type()].ptr, 2, false));
	}
}

