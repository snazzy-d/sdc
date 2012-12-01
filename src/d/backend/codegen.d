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
	
	return cg.visit(modules);
}

import d.ast.declaration;
import d.ast.statement;
import d.ast.expression;
import d.ast.type;

import d.backend.declaration;
import d.backend.statement;
import d.backend.expression;
import d.backend.string;
import d.backend.type;

final class CodeGenPass {
	private DeclarationGen declarationGen;
	private StatementGen statementGen;
	private AddressOfGen addressOfGen;
	private ExpressionGen expressionGen;
	private TypeGen typeGen;
	
	private StringGen stringGen;
	
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
		
		stringGen		= new StringGen(this);
		
		druntimeGen		= new DruntimeGen(this);
		
		// TODO: types in context.
		context = LLVMContextCreate();
		builder = LLVMCreateBuilderInContext(context);
	}
	
	LLVMModuleRef visit(Module[] modules) {
		//*
		auto oldModule = dmodule;
		scope(exit) dmodule = oldModule;
		//*/
		dmodule = LLVMModuleCreateWithNameInContext(modules.back.location.filename.toStringz(), context);
		
		// Dump module content on failure (for debug purpose).
		scope(failure) LLVMDumpModule(dmodule);
		
		foreach(m; modules) {
			visit(m);
		}
		
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

