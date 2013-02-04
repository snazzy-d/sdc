module d.backend.evaluator;

import d.backend.codegen;

import d.ast.expression;
import d.ast.type;

import d.semantic.evaluator;

import util.visitor;

import llvm.c.core;
import llvm.c.executionEngine;

import std.algorithm;
import std.array;

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
		return new CompileTimeTupleExpression(e.location, e.values.map!(e => evaluate(e)).array());
	}
	
	CompileTimeExpression visit(BitCastExpression e) {
		// XXX: hack to get enums work.
		import d.ast.adt;
		if(auto t = cast(EnumType) e.type) {
			return evaluate(e.expression);
		}
		
		return jit(e);
	}
	
	// Actual JIT
	private CompileTimeExpression jit(Expression e) {
		if(auto t = cast(IntegerType) e.type) {
			auto returned = jitInteger(e);
			
			if(t.type % 2) {
				return new IntegerLiteral!false(e.location, returned, t);
			} else {
				return new IntegerLiteral!true(e.location, returned, t);
			}
		} else if(cast(BooleanType) e.type) {
			auto returned = jitInteger(e);
			
			return new BooleanLiteral(e.location, !!returned);
		} else if(auto t = cast(SliceType) e.type) {
			if(cast(CharacterType) t.type) {
				auto returned = jitString(e);
				
				return new StringLiteral(e.location, returned);
			}
		}
		
		assert(0, "Only able to JIT integers and booleans, " ~ typeid(e).toString() ~ " given.");
	}
	
	private auto jitInteger(Expression e) {
		auto result = codeGen.ctfe(e, executionEngine);
		// XXX: dispose value ?
		
		return cast(int) LLVMGenericValueToInt(result, true);
	}
	
	private string jitString(Expression e) {
		// XXX: run twice ! Most inneffiscient way :D
		import d.ast.declaration;
		import d.ast.adt;
		
		auto lt = new IntegerType(e.location, Integer.Ulong);
		auto lf = new FieldDeclaration(new VariableDeclaration(e.location, lt, "length", new DefaultInitializer(lt)), 0);
		auto lengthExpression = new FieldExpression(e.location, e, lf);
		lengthExpression.type = lt;
		
		auto lengthResult = codeGen.ctfe(lengthExpression, executionEngine);
		auto length = cast(size_t) LLVMGenericValueToInt(lengthResult, true);
		
		auto pt = new PointerType(e.location, new CharacterType(e.location, Character.Char));
		auto pf = new FieldDeclaration(new VariableDeclaration(e.location, pt, "ptr", new DefaultInitializer(pt)), 1);
		auto ptrExpression = new FieldExpression(e.location, e, pf);
		ptrExpression.type = pt;
		
		auto ptrResult = codeGen.ctfe(ptrExpression, executionEngine);
		auto ptr = cast(char*) LLVMGenericValueToPointer(ptrResult);
		
		return ptr[0 .. length].idup;
	}
}

