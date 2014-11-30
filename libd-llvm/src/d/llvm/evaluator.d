module d.llvm.evaluator;

import d.llvm.codegen;

import d.ir.expression;
import d.ir.type;

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
		auto ret = new CompileTimeTupleExpression(e.location, e.type, e.values.map!(e => evaluate(e)).array());
		ret.type = e.type;
		
		return ret;
	}
	/+
	CompileTimeExpression visit(BitCastExpression e) {
		// XXX: hack to get enums work.
		import d.ast.adt;
		if(auto t = cast(EnumType) e.type) {
			return evaluate(e.expression);
		}
		
		return jit(e);
	}
	+/
	// Actual JIT
	private CompileTimeExpression jit(Expression e) {
		auto type = peelAlias(e.type).type;
		
		if(auto et = cast(EnumType) type) {
			type = et.denum.type;
		}
		
		if(auto t = cast(BuiltinType) type) {
			auto k = t.kind;
			if (isIntegral(k)) {
				auto returned = evalIntegral(e);
				
				return isSigned(k)
					? new IntegerLiteral!true(e.location, returned, k)
					: new IntegerLiteral!false(e.location, returned, k);
			} else if (k == TypeKind.Bool) {
				return new BooleanLiteral(e.location, !!evalIntegral(e));
			}
		}
		
		if(auto t = cast(SliceType) type) {
			if(auto c = cast(BuiltinType) peelAlias(t.sliced).type) {
				if(c.kind == TypeKind.Char) {
					return new StringLiteral(e.location, evalString(e));
				}
			}
		}
		
		assert(0, "Only able to JIT integers, booleans and strings, " ~ type.toString(codeGen.context) ~ " given.");
	}
	
	ulong evalIntegral(Expression e) {
		return codeGen.ctfe(e, executionEngine);
	}
	
	string evalString(Expression e) {
		return codeGen.ctString(e, executionEngine);
	}
}

