module d.backend.evaluator;

import d.backend.codegen;

import d.ast.expression;
import d.ast.type;

import d.pass.evaluator;

import util.visitor;

import llvm.c.core;
import llvm.c.executionEngine;

// In order to JIT.
extern(C) void _d_assert();
extern(C) void _d_array_bounds();

final class LLVMEvaluator : Evaluator {
	private CodeGenPass codeGen;
	
	private LLVMExecutionEngineRef executionEngine;
	
	this(CodeGenPass codeGen) {
		this.codeGen = codeGen;
		
		char* errorPtr;
		auto creationError = LLVMCreateJITCompilerForModule(&executionEngine, codeGen.dmodule, 0, &errorPtr);
		if(creationError) {
			import std.c.string;
			import std.stdio;
			writeln(errorPtr[0 .. strlen(errorPtr)]);
			writeln("Cannot create execution engine ! Exiting...");
			
			assert(0);
		}
	}
	
	CompileTimeExpression evaluate(Expression e) {
		return this.dispatch!(e => jit(e))(e);
	}
	
	private CompileTimeExpression jit(Expression e) {
		assert(cast(IntegerType) e.type, "Only able to JIT integers.");
		
		auto result = codeGen.ctfe(e, executionEngine);
		
		auto returned = cast(int) LLVMGenericValueToInt(result, true);
		
		return makeLiteral(e.location, returned);
	}
	
	CompileTimeExpression visit(BooleanLiteral e) {
		return e;
	}
	
	CompileTimeExpression visit(IntegerLiteral!true e) {
		return e;
	}
	
	CompileTimeExpression visit(IntegerLiteral!false e) {
		return e;
	}
	
	CompileTimeExpression visit(FloatLiteral e) {
		return e;
	}
	
	CompileTimeExpression visit(CharacterLiteral e) {
		return e;
	}
	
	CompileTimeExpression visit(NullLiteral e) {
		return e;
	}
}

