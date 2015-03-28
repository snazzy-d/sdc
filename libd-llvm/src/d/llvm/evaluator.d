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
		
	this(CodeGenPass codeGen) {
		this.codeGen = codeGen;
	}

	auto createExecutionEngine(LLVMModuleRef dmodule) {
		char* errorPtr;
		
		LLVMExecutionEngineRef executionEngine;
		
		auto creationError = LLVMCreateMCJITCompilerForModule(&executionEngine, dmodule,  null, 0,  &errorPtr);
		if (creationError) {
			scope(exit) LLVMDisposeMessage(errorPtr);
			
			import std.c.string;
			auto error = errorPtr[0 .. strlen(errorPtr)].idup;
			
			import std.stdio;
			writeln(error);
			assert(0, "Cannot create execution engine ! Exiting...");
		}
		
		return executionEngine;
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
			auto et = t.element.getCanonical();
			if (et.kind == TypeKind.Builtin && et.builtin == BuiltinType.Char) {
				return new StringLiteral(e.location, evalString(e));
			}
		}
		
		assert(0, "Only able to JIT integers, booleans and strings, " ~ t.toString(codeGen.context) ~ " given.");
	}
	
	ulong evalIntegral(Expression e) {
		scope(failure) LLVMDumpModule(codeGen.dmodule);
		
		// Add ctfe function header to module
		auto funType = LLVMFunctionType(codeGen.visit(e.type), null, 0, false);
		auto fun = LLVMAddFunction(codeGen.dmodule, "__ctfe", funType);
		scope(exit) LLVMDeleteFunction(fun);
		
		auto backupCurrentBB = LLVMGetInsertBlock(codeGen.builder);
		scope(exit) {
			if (backupCurrentBB) {
				LLVMPositionBuilderAtEnd(codeGen.builder, backupCurrentBB);
			} else {
				LLVMClearInsertionPosition(codeGen.builder);
			}
		}
		auto bodyBB = LLVMAppendBasicBlockInContext(codeGen.llvmCtx, fun, "");
		LLVMPositionBuilderAtEnd(codeGen.builder, bodyBB);
		
		// Generate function's body.
		import d.llvm.expression;
		auto eg = ExpressionGen(codeGen);
		LLVMBuildRet(codeGen.builder, eg.visit(e));
		codeGen.checkModule();
		
		// Create a temporary execution engine for our LLVM module
		auto executionEngine = createExecutionEngine(codeGen.dmodule);
		scope(exit) {
			char* errorPtr;
			LLVMModuleRef outMod;
			auto removeError = LLVMRemoveModule(executionEngine, codeGen.dmodule, &outMod, &errorPtr);
			if (removeError) {
				scope(exit) LLVMDisposeMessage(errorPtr);
				import std.c.string;
				auto error = errorPtr[0 .. strlen(errorPtr)].idup;
				
				import std.stdio;
				writeln(error);
				assert(0, "Cannot remove module from execution engine ! Exiting...");
			}
			LLVMDisposeExecutionEngine(executionEngine);
		}
		
		auto result = LLVMRunFunction(executionEngine, fun, 0, null);
		scope(exit) LLVMDisposeGenericValue(result);
		
		return LLVMGenericValueToInt(result, true);
	}
	
	string evalString(Expression e) in {
		// FIXME: newtype
		// assert(cast(SliceType) peelAlias(e.type).type, "this only CTFE strings.");
	} body {
		scope(failure) LLVMDumpModule(codeGen.dmodule);

		// Create a global variable to hold the returned string.
		auto stringType = codeGen.visit(e.type);
		auto receiver = LLVMAddGlobal(codeGen.dmodule, stringType, "__ctString");
		scope(exit) LLVMDeleteGlobal(receiver);
		
		// Initialize __ctString
		LLVMValueRef[2] constInit = [ LLVMConstInt(LLVMInt64TypeInContext(codeGen.llvmCtx), 0, false),
			LLVMConstNull(LLVMPointerType(LLVMInt8TypeInContext(codeGen.llvmCtx), 0)) ];
		LLVMSetInitializer(receiver, LLVMConstStructInContext(codeGen.llvmCtx, constInit.ptr, 2, false));
		
		// Generate function signature
		auto funType = LLVMFunctionType(LLVMInt64TypeInContext(codeGen.llvmCtx), null, 0, false);
		auto fun = LLVMAddFunction(codeGen.dmodule, "__ctfe", funType);
		scope(exit) LLVMDeleteFunction(fun);
		
		auto backupCurrentBB = LLVMGetInsertBlock(codeGen.builder);
		scope(exit) {
			if (backupCurrentBB) {
				LLVMPositionBuilderAtEnd(codeGen.builder, backupCurrentBB);
			} else {
				LLVMClearInsertionPosition(codeGen.builder);
			}
		}
		
		auto bodyBB = LLVMAppendBasicBlockInContext(codeGen.llvmCtx, fun, "");
		LLVMPositionBuilderAtEnd(codeGen.builder, bodyBB);
		
		// Generate function's body.
		import d.llvm.expression;
		auto eg = ExpressionGen(codeGen);
		
		LLVMBuildStore(codeGen.builder, eg.visit(e), receiver);
		// FIXME This is 64bit only code.
		auto ptrToInt = LLVMBuildPtrToInt(codeGen.builder, receiver, LLVMInt64TypeInContext(codeGen.llvmCtx),"");
		LLVMBuildRet(codeGen.builder, ptrToInt);
		
		codeGen.checkModule();
		
		auto executionEngine = createExecutionEngine(codeGen.dmodule);
		scope(exit) {
			char* errorPtr;
			LLVMModuleRef outMod;
			auto removeError = LLVMRemoveModule(executionEngine, codeGen.dmodule, &outMod, &errorPtr);
			if (removeError) {
				scope (exit) LLVMDisposeMessage(errorPtr);
				import std.c.string;
				auto error = errorPtr[0 .. strlen(errorPtr)].idup;
				
				import std.stdio;
				writeln(error);
				assert(0, "Cannot remove module from execution engine ! Exiting...");
			}
			LLVMDisposeExecutionEngine(executionEngine);
		}
		auto result = LLVMRunFunction(executionEngine, fun, 0, null);
		scope(exit) LLVMDisposeGenericValue(result);

		// FIXME This only works for 64 bit platforms because the retval
		// of the "__ctfe" is specifically a i64.  This is due to MCJIT
		// not supporting pointer return values directly at this time. 
		auto sAsInt = LLVMGenericValueToInt(result, false);
		string s = *cast(string*)cast(void*)sAsInt;
		return s.idup;
	}
}

