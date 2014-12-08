module d.llvm.evaluator;

import d.llvm.codegen;

import d.ir.expression;

import d.semantic.evaluator;

import util.visitor;

import llvm.c.core;
import llvm.c.executionEngine;

import std.algorithm;
import std.array;

// In order to JIT.
extern(C) void _d_assert(string, int);
extern(C) void _d_assert_msg(string, string, int);
extern(C) void _d_arraybounds(string, int);
extern(C) void* _d_allocmemory(size_t);

final class LLVMEvaluator : Evaluator {
	private CodeGenPass codeGen;
	
	private LLVMExecutionEngineRef executionEngine;
	
	this(LLVMExecutionEngineRef executionEngine, CodeGenPass codeGen) {
		this.codeGen = codeGen;
		this.executionEngine = executionEngine;
	}
	
	CompileTimeExpression evaluate(Expression e) {
		if (auto ce = cast(CompileTimeExpression) e) {
			return ce;
		}
		
		return this.dispatch!(e => jit(e))(e);
	}
	
	CompileTimeExpression visit(TupleExpression e) {
		return new CompileTimeTupleExpression(e.location, e.type, e.values.map!(e => evaluate(e)).array());
	}
	
	// Actual JIT
	private CompileTimeExpression jit(Expression e) {
		auto t = e.type.getCanonical();
		
		import d.ir.type;
		if (t.kind == TypeKind.Enum) {
			t = t.denum.type;
		}
		
		if (t.kind == TypeKind.Builtin) {
			auto k = t.builtin;
			if (isIntegral(k)) {
				auto returned = evalIntegral(e);
				
				return isSigned(k)
					? new IntegerLiteral!true(e.location, returned, k)
					: new IntegerLiteral!false(e.location, returned, k);
			} else if (k == BuiltinType.Bool) {
				return new BooleanLiteral(e.location, !!evalIntegral(e));
			}
		}
		
		if (t.kind == TypeKind.Slice) {
			auto et = t.getElement().getCanonical();
			if (et.kind == TypeKind.Builtin && t.builtin == BuiltinType.Char) {
				return new StringLiteral(e.location, evalString(e));
			}
		}
		
		assert(0, "Only able to JIT integers, booleans and strings, " ~ t.toString(codeGen.context) ~ " given.");
	}
	
	ulong evalIntegral(Expression e) {
		return codeGen.ctfe(e, executionEngine);
	}
	
	string evalString(Expression e) {
		return codeGen.ctString(e, executionEngine);
	}
}

