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
extern(C) void _d_assert();
extern(C) void _d_assert_msg();
extern(C) void _d_array_bounds();
extern(C) void* _d_allocmemory();

final class LLVMEvaluator : Evaluator {
	private CodeGenPass codeGen;
	
	private LLVMExecutionEngineRef executionEngine;
	
	this(LLVMExecutionEngineRef executionEngine, CodeGenPass codeGen) {
		this.codeGen = codeGen;
		this.executionEngine = executionEngine;
	}
	
	CompileTimeExpression evaluate(Expression e) {
		return this.dispatch!(e => jit(e))(e);
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
	
	CompileTimeExpression visit(StringLiteral e) {
		return e;
	}
	
	CompileTimeExpression visit(TupleExpression e) {
		auto ret = new CompileTimeTupleExpression(e.location, e.values.map!(e => evaluate(e)).array());
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
		auto type = e.type.type;
		
		if(auto et = cast(EnumType) type) {
			type = et.denum.type;
		}
		
		if(auto t = cast(BuiltinType) type) {
			auto k = t.kind;
			if(isIntegral(k)) {
				auto returned = jitInteger(e);
				
				if(isSigned(k)) {
					return new IntegerLiteral!true(e.location, returned, k);
				} else {
					return new IntegerLiteral!false(e.location, returned, k);
				}
			} else if(k == TypeKind.Bool) {
				auto returned = jitInteger(e);
				
				return new BooleanLiteral(e.location, !!returned);
			}
		}
		/+
		if(auto t = cast(SliceType) e.type) {
			if(cast(CharacterType) t.type) {
				auto returned = jitString(e);
				
				return new StringLiteral(e.location, returned);
			}
		}
		+/
		assert(0, "Only able to JIT integers and booleans, " ~ type.toString() ~ " given.");
	}
	
	private auto jitInteger(Expression e) {
		return codeGen.ctfe(e, executionEngine);
	}
	
	private string jitString(Expression e) {
		return codeGen.ctString(e, executionEngine);
	}
}

