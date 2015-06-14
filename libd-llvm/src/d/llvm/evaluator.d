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

	CompileTimeExpression evaluate(Expression e) {
		if (auto ce = cast(CompileTimeExpression) e) {
			return ce;
		}
		
		// XXX: Work around not being able to pass e down.
		static Expression statice;
		auto oldStatice = statice;
		statice = e;
		scope(exit) statice = oldStatice;

		static CodeGenPass staticCodeGen;
		auto oldStaticCodeGen = staticCodeGen;
		staticCodeGen = codeGen;
		scope(exit) staticCodeGen = oldStaticCodeGen;

		// We agressively JIT all CTFE
		return jit!(function CompileTimeExpression(void[] p) {
			return JitRepacker(staticCodeGen, statice.location, p).visit(statice.type);
		})(e);
	}
	
	ulong evalIntegral(Expression e) in {
		auto t = e.type.getCanonical();
		while (t.kind = TypeKing.Enum) {
			t = t.denum.type.getCanonical();
		}

		assert(t.kind == TypeKind.Builtin);

		auto bt = t.builtin;
		assert(isIntegral(bt) || bt == BuiltinType.Bool);
	} body {
		return jit!(function ulong(ulong r) {
			return r;
		}, JitReturn.Direct)(e);
	}

	string evalString(Expression e) in {
		auto t = e.type.getCanonical();
		assert(t.kind = TypeKind.Slice);
		
		auto et = t.element.getCanonical();
		assert(et.builtin = BuiltinType.Char);
	} body {
		return jit!(function string(void[] p) in {
			assert(p.length == string.sizeof);
		} body {
			auto s = *(cast(string*) p.ptr);
			return s.idup;
		})(e);
	}
	
	private auto jit(alias handler, JitReturn R = JitReturn.Indirect)(Expression e) {
		scope(failure) LLVMDumpModule(codeGen.dmodule);

		// Create a global variable to hold the returned blob.
		auto type = codeGen.visit(e.type);

		static if (R == JitReturn.Direct) {
			auto returnType = type;
		} else {
			auto buffer = LLVMAddGlobal(codeGen.dmodule, type, "__ctBuf");
			scope(exit) LLVMDeleteGlobal(buffer);
			
			LLVMSetInitializer(buffer, LLVMGetUndef(type));

			import llvm.c.target;
			auto size = LLVMStoreSizeOfType(codeGen.targetData, type);

			auto returnType = LLVMIntPtrTypeInContext(codeGen.llvmCtx, codeGen.targetData);
		}

		// Generate function signature
		auto funType = LLVMFunctionType(returnType, null, 0, false);
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
		auto value = ExpressionGen(codeGen).visit(e);

		static if (R == JitReturn.Direct) {
			LLVMBuildRet(codeGen.builder, value);
		} else {
			LLVMBuildStore(codeGen.builder, value, buffer);
			auto ptrToInt = LLVMBuildPtrToInt(codeGen.builder, buffer, LLVMIntPtrTypeInContext(codeGen.llvmCtx, codeGen.targetData), "");
			LLVMBuildRet(codeGen.builder, ptrToInt);
		}

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


		static if (R == JitReturn.Direct) {
			return handler(LLVMGenericValueToInt(result, true));
		} else {
			// FIXME This only works for 64 bit platforms because the retval
			// of the "__ctfe" is specifically a i64. This is due to MCJIT
			// not supporting pointer return values directly at this time. 
			auto asInt = LLVMGenericValueToInt(result, false);
			return handler((cast(void*) asInt)[0 .. size]);
		}
	}

	private auto createExecutionEngine(LLVMModuleRef dmodule) {
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
}

private:

enum JitReturn {
	Direct,
	Indirect,
}

struct JitRepacker {
	CodeGenPass codeGen;
	
	import d.location;
	Location location;

	void[] p;
	
	this(CodeGenPass codeGen, Location location, void[] p) {
		this.codeGen = codeGen;
		this.p = p;
	}
	
	import d.ir.type, d.ir.symbol;
	CompileTimeExpression visit(Type t) in {
		import llvm.c.target;
		auto size = LLVMStoreSizeOfType(codeGen.targetData, codeGen.visit(t));

		import std.conv;
		assert(
			size == p.length,
			"Buffer of length " ~ p.length.to!string() ~
				" when " ~ size.to!string() ~ " was expected"
		);
	} out(result) {
		// FIXME: This does not always pass now.
		// assert(result.type == t, "Result type do not match");
		assert(p.length == 0, "Remaining data in the buffer");
	} body {
		return t.accept(this);
	}
	
	T get(T)() {
		scope(exit) p = p[T.sizeof .. $];
		return *(cast(T*) p.ptr);
	}

	CompileTimeExpression visit(BuiltinType t) {
		ulong raw;
		switch(t) with(BuiltinType) {
			case Bool :
				return new BooleanLiteral(location, get!bool());

			case Byte, Ubyte:
				raw = get!ubyte();
				goto HandleIntegral;
			
			case Short, Ushort:
				raw = get!ushort();
				goto HandleIntegral;
			
			case Int, Uint:
				raw = get!uint();
				goto HandleIntegral;
			
			case Long, Ulong:
				raw = get!ulong();
				goto HandleIntegral;
			
			HandleIntegral:
				return isSigned(t)
					? new IntegerLiteral!true(location, raw, t)
					: new IntegerLiteral!false(location, raw, t);

			default:
				assert(0, "Not implemented");
		}
	}
	
	CompileTimeExpression visitPointerOf(Type t) {
		assert(0, "Not implemented");
	}
	
	CompileTimeExpression visitSliceOf(Type t) {
		if (t.kind == TypeKind.Builtin && t.builtin == BuiltinType.Char && t.qualifier == TypeQualifier.Immutable) {
			return new StringLiteral(location, get!string().idup);
		}

		assert(0, "Not Implemented.");
	}
	
	CompileTimeExpression visitArrayOf(uint size, Type t) {
		import llvm.c.target;
		uint elementSize = cast(uint) LLVMStoreSizeOfType(codeGen.targetData, codeGen.visit(t));

		CompileTimeExpression[] elements;
		elements.reserve(size);
		
		auto buf = p;
		uint start = 0;
		scope(exit) p = buf[start .. $];
		
		for (uint i = 0; i < size; i++) {
			uint end = start + elementSize;
			p = buf[start .. end];
			start = end;
			elements ~= visit(t);
		}

		return new CompileTimeTupleExpression(location, t.getArray(size), elements);
	}
	
	CompileTimeExpression visit(Struct s) {
		auto type = codeGen.buildStructType(s);
		auto count = LLVMCountStructElementTypes(type);

		// Hopefully we will be able to use http://reviews.llvm.org/D10148
		LLVMTypeRef[] elementTypes;
		elementTypes.length = count;

		import llvm.c.target;
		LLVMGetStructElementTypes(type, elementTypes.ptr);

		auto buf = p;
		auto size = LLVMStoreSizeOfType(codeGen.targetData, type);
		scope(exit) p = buf[size .. $];

		CompileTimeExpression[] elements;
		
		uint i = 0;
		foreach (m; s.members) {
			if (auto f = cast(Field) m) {
				scope(success) i++;

				assert(f.index == i, "fields are out of order");
				auto t = f.type;

				auto start = LLVMOffsetOfElement(codeGen.targetData, type, i);
				auto elementType = elementTypes[i];

				auto fieldSize = LLVMStoreSizeOfType(codeGen.targetData, elementType);
				auto end = start + fieldSize;

				p = buf[start .. end];
				elements ~= visit(t);
			}
		}
		
		return new CompileTimeTupleExpression(location, Type.get(s), elements);
	}
	
	CompileTimeExpression visit(Class c) {
		assert(0, "Not Implemented.");
	}
	
	CompileTimeExpression visit(Enum e) {
		auto r = visit(e.type);
		r.type = Type.get(e);
		return r;
	}
	
	CompileTimeExpression visit(TypeAlias a) {
		auto r = visit(a.type);
		r.type = Type.get(a);
		return r;
	}
	
	CompileTimeExpression visit(Interface i) {
		assert(0, "Not Implemented.");
	}
	
	CompileTimeExpression visit(Union u) {
		assert(0, "Not Implemented.");
	}
	
	CompileTimeExpression visit(Function f) {
		assert(0, "Not Implemented.");
	}
	
	CompileTimeExpression visit(Type[] seq) {
		assert(0, "Not Implemented.");
	}
	
	CompileTimeExpression visit(FunctionType f) {
		assert(0, "Not Implemented.");
	}
	
	CompileTimeExpression visit(TypeTemplateParameter p) {
		assert(0, "Not implemented.");
	}
}
