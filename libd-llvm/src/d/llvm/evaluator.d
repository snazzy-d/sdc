module d.llvm.evaluator;

import d.llvm.codegen;

import d.ir.expression;

import d.semantic.evaluator;

import util.visitor;

import llvm.c.core;
import llvm.c.executionEngine;

// In order to JIT.
extern(C) void _d_assert(string, int);
extern(C) void _d_assert_msg(string, string, int);
extern(C) void _d_arraybounds(string, int);

extern(C) void* __sd_gc_tl_malloc(size_t size) {
	import core.memory;
	return GC.malloc(size);
}

extern(C) void* __sd_array_alloc(size_t size) {
	import core.memory;
	return GC.malloc(size);
}

extern(C) void __sd_array_outofbounds(string file, int line) {
	_d_arraybounds(file, line);
}

final class LLVMEvaluator : Evaluator {
	private CodeGen pass;
	alias pass this;
	
	this(CodeGen pass) {
		this.pass = pass;
	}
	
	CompileTimeExpression evaluate(Expression e) {
		if (auto ce = cast(CompileTimeExpression) e) {
			return ce;
		}
		
		// We agressively JIT all CTFE
		return jit!(function CompileTimeExpression(
			CodeGen pass,
			Expression e,
			void[] p,
		) {
			return JitRepacker(pass, e.location, p).visit(e.type);
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
		return jit!(function string(CodeGen pass, Expression e, void[] p) in {
			assert(p.length == string.sizeof);
		} body {
			auto s = *(cast(string*) p.ptr);
			return s.idup;
		})(e);
	}
	
	private auto jit(
		alias handler,
		JitReturn R = JitReturn.Indirect,
	)(Expression e) {
		scope(failure) LLVMDumpModule(dmodule);
		
		// Create a global variable to hold the returned blob.
		import d.llvm.type;
		auto type = TypeGen(pass).visit(e.type);
		
		static if (R == JitReturn.Direct) {
			auto returnType = type;
		} else {
			auto buffer = LLVMAddGlobal(dmodule, type, "__ctBuf");
			scope(exit) LLVMDeleteGlobal(buffer);
			
			LLVMSetInitializer(buffer, LLVMGetUndef(type));
			
			import llvm.c.target;
			auto size = LLVMStoreSizeOfType(targetData, type);
			auto returnType = LLVMInt64TypeInContext(llvmCtx);
		}
		
		// Generate function signature
		auto funType = LLVMFunctionType(returnType, null, 0, false);
		auto fun = LLVMAddFunction(dmodule, "__ctfe", funType);
		scope(exit) LLVMDeleteFunction(fun);
		
		// Generate function's body. Warning: horrible hack.
		import d.llvm.local;
		auto lg = LocalGen(pass, Mode.Eager);
		auto builder = lg.builder;
		
		auto bodyBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "");
		LLVMPositionBuilderAtEnd(builder, bodyBB);
		
		import d.llvm.expression;
		auto value = ExpressionGen(&lg).visit(e);
		
		static if (R == JitReturn.Direct) {
			LLVMBuildRet(builder, value);
		} else {
			LLVMBuildStore(builder, value, buffer);
			// FIXME This is 64bit only code.
			auto ptrToInt = LLVMBuildPtrToInt(
				builder,
				buffer,
				LLVMInt64TypeInContext(llvmCtx),
				"",
			);
			
			LLVMBuildRet(builder, ptrToInt);
		}
		
		checkModule();
		
		auto ee = createExecutionEngine(dmodule);
		scope(exit) destroyExecutionEngine(ee, dmodule);
		
		auto result = LLVMRunFunction(ee, fun, 0, null);
		scope(exit) LLVMDisposeGenericValue(result);
		
		static if (R == JitReturn.Direct) {
			return handler(LLVMGenericValueToInt(result, true));
		} else {
			// FIXME This only works for 64 bit platforms because the retval
			// of the "__ctfe" is specifically a i64. This is due to MCJIT
			// not supporting pointer return values directly at this time. 
			auto asInt = LLVMGenericValueToInt(result, false);
			return handler(pass, e, (cast(void*) asInt)[0 .. size]);
		}
	}
}

package:
auto createExecutionEngine(LLVMModuleRef dmodule) {
	char* errorPtr;
	LLVMExecutionEngineRef ee;
	auto creationError = LLVMCreateMCJITCompilerForModule(
		&ee,
		dmodule,
		null,
		0,
		&errorPtr,
	);
	
	if (creationError) {
		scope(exit) LLVMDisposeMessage(errorPtr);
		
		import std.c.string;
		auto error = errorPtr[0 .. strlen(errorPtr)].idup;
		
		import std.stdio;
		writeln(error);
		assert(0, "Cannot create execution engine ! Exiting...");
	}
	
	return ee;
}

auto destroyExecutionEngine(LLVMExecutionEngineRef ee, LLVMModuleRef dmodule) {
	char* errorPtr;
	LLVMModuleRef outMod;
	auto removeError = LLVMRemoveModule(
		ee,
		dmodule,
		&outMod,
		&errorPtr,
	);
	
	if (removeError) {
		scope (exit) LLVMDisposeMessage(errorPtr);
		import std.c.string;
		auto error = errorPtr[0 .. strlen(errorPtr)].idup;
		
		import std.stdio;
		writeln(error);
		assert(
			0,
			"Cannot remove module from execution engine ! Exiting..."
		);
	}
	
	LLVMDisposeExecutionEngine(ee);
}

private:

enum JitReturn {
	Direct,
	Indirect,
}

struct JitRepacker {
	CodeGen pass;
	alias pass this;
	
	import d.context.location;
	Location location;
	
	void[] p;
	
	this(CodeGen pass, Location location, void[] p) {
		this.pass = pass;
		this.p = p;
	}
	
	import d.ir.type, d.ir.symbol;
	CompileTimeExpression visit(Type t) in {
		import d.llvm.type, llvm.c.target;
		auto size = LLVMStoreSizeOfType(targetData, TypeGen(pass).visit(t));
		
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
				return new IntegerLiteral(location, raw, t);
			
			default:
				assert(0, "Not implemented");
		}
	}
	
	CompileTimeExpression visitPointerOf(Type t) {
		assert(0, "Not implemented");
	}
	
	CompileTimeExpression visitSliceOf(Type t) {
		if (
			t.kind == TypeKind.Builtin &&
			t.builtin == BuiltinType.Char &&
			t.qualifier == TypeQualifier.Immutable
		) {
			return new StringLiteral(location, get!string().idup);
		}
		
		assert(0, "Not Implemented.");
	}
	
	CompileTimeExpression visitArrayOf(uint size, Type t) {
		import d.llvm.type, llvm.c.target;
		uint elementSize = cast(uint) LLVMStoreSizeOfType(
			targetData,
			TypeGen(pass).visit(t),
		);
		
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
		
		return new CompileTimeTupleExpression(
			location,
			t.getArray(size),
			elements,
		);
	}
	
	CompileTimeExpression visit(Struct s) {
		import d.llvm.type;
		auto type = TypeGen(pass).visit(s);
		
		import llvm.c.target;
		auto size = LLVMStoreSizeOfType(targetData, type);
		
		auto buf = p;
		scope(exit) p = buf[size .. $];
		
		CompileTimeExpression[] elements;
		
		uint i = 0;
		foreach (m; s.members) {
			if (auto f = cast(Field) m) {
				scope(success) i++;
				
				assert(f.index == i, "fields are out of order");
				auto t = f.type;
				
				auto start = LLVMOffsetOfElement(targetData, type, i);
				auto elementType = LLVMStructGetTypeAtIndex(type, i);
				
				auto fieldSize = LLVMStoreSizeOfType(targetData, elementType);
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
		// TODO: build implicit cast.
		return visit(e.type);
	}
	
	CompileTimeExpression visit(TypeAlias a) {
		// TODO: build implicit cast.
		return visit(a.type);
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
	
	CompileTimeExpression visit(Pattern p) {
		assert(0, "Not implemented.");
	}
	
	import d.ir.error;
	CompileTimeExpression visit(CompileError e) {
		assert(0, "Not implemented.");
	}
}
