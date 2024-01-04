module d.llvm.evaluator;

import d.llvm.codegen;

import d.ir.constant;
import d.ir.expression;

import d.semantic.evaluator;

import util.visitor;

import llvm.c.core;
import llvm.c.executionEngine;

// In order to JIT, we redirect some call from libsdrt to druntime.
extern(C) {
	/**
	 * Memory allocation, forward to GC
	 */
	void* __sd_gc_alloc(size_t size) {
		import core.memory;
		return GC.malloc(size);
	}

	void* __sd_gc_array_alloc(size_t size) {
		import core.memory;
		return GC.malloc(size);
	}

	/**
	 * Forward bound check routines.
	 */
	void _d_arraybounds(string, int);
	void __sd_array_outofbounds(string file, int line) {
		_d_arraybounds(file, line);
	}

	/**
	 * Forward contract routines.
	 */
	void _d_assert(string, int);
	void __sd_assert_fail(string file, int line) {
		_d_assert(file, line);
	}

	void _d_assert_msg(string, string, int);
	void __sd_assert_fail_msg(string msg, string file, int line) {
		_d_assert_msg(msg, file, line);
	}

	/**
	 * Exception facilities are using a subset of libsdrt compiled with
	 * DMD called libsdmd. We need to anchor some functions here.
	 */
	void __sd_eh_throw(void*);
	immutable __anchor_sd_eh_throw = &__sd_eh_throw;
}

final class LLVMEvaluator : Evaluator {
private:
	import d.llvm.global;
	GlobalGen globalGen;

	alias pass this;
	@property
	auto pass() {
		return globalGen.pass;
	}

public:
	this(CodeGen pass) {
		globalGen = GlobalGen(pass, "sdc.jit", Mode.Eager);
	}

	CompileTimeExpression evaluate(Expression e) {
		if (auto ce = cast(CompileTimeExpression) e) {
			return ce;
		}

		// We agressively JIT all CTFE.
		auto c =
			jit!(function Constant(CodeGen pass, Expression e, void[] buffer) {
				return JitRepacker(pass, buffer).visit(e.type);
			})(e);

		return new ConstantExpression(e.location, c);
	}

	ulong evalIntegral(Expression e) in {
		auto t = e.type.getCanonical();
		while (t.kind = TypeKing.Enum) {
			t = t.denum.type.getCanonical();
		}

		assert(t.kind == TypeKind.Builtin);

		auto bt = t.builtin;
		assert(isIntegral(bt) || bt == BuiltinType.Bool);
	} do {
		return jit!(function ulong(ulong r) {
			return r;
		}, JitReturn.Direct)(e);
	}

	string evalString(Expression e) in {
		auto t = e.type.getCanonical();
		assert(t.kind = TypeKind.Slice);

		auto et = t.element.getCanonical();
		assert(et.builtin = BuiltinType.Char);
	} do {
		return jit!(function string(CodeGen pass, Expression e, void[] p)
			in (p.length == string.sizeof) {
				auto s = *(cast(string*) p.ptr);
				return s.idup;
			})(e);
	}

	private
	auto jit(alias handler, JitReturn R = JitReturn.Indirect)(Expression e) {
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
			auto returnType = i64;
		}

		// Generate function signature.
		auto funType = LLVMFunctionType(returnType, null, 0, false);
		auto fun = LLVMAddFunction(dmodule, "__ctfe", funType);
		scope(exit) LLVMDeleteFunction(fun);

		// Generate function's body. Warning: horrible hack.
		import d.llvm.local;
		auto lg = LocalGen(&globalGen);
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
			auto ptrToInt = LLVMBuildPtrToInt(builder, buffer, i64, "");

			LLVMBuildRet(builder, ptrToInt);
		}

		globalGen.checkModule();

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

	import d.ir.symbol;
	auto createTestStub(Function f) {
		// Make sure the function we want to call is ready to go.
		auto callee = globalGen.declare(f);

		// Generate function's body. Warning: horrible hack.
		import d.llvm.local;
		auto lg = LocalGen(&globalGen);
		auto builder = lg.builder;

		auto funType = LLVMFunctionType(i64, null, 0, false);
		auto fun = LLVMAddFunction(dmodule, "__unittest", funType);

		// Personality function to handle exceptions.
		LLVMSetPersonalityFn(fun,
		                     globalGen.declare(pass.object.getPersonality()));

		auto callBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "call");
		auto thenBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "then");
		auto lpBB = LLVMAppendBasicBlockInContext(llvmCtx, fun, "lp");

		LLVMPositionBuilderAtEnd(builder, callBB);
		LLVMBuildInvoke2(builder, funType, callee, null, 0, thenBB, lpBB, "");

		LLVMPositionBuilderAtEnd(builder, thenBB);
		LLVMBuildRet(builder, LLVMConstInt(i64, 0, false));

		// Build the landing pad.
		LLVMTypeRef[2] lpTypes = [llvmPtr, i32];
		auto lpType = LLVMStructTypeInContext(llvmCtx, lpTypes.ptr,
		                                      lpTypes.length, false);

		LLVMPositionBuilderAtEnd(builder, lpBB);
		auto landingPad = LLVMBuildLandingPad(builder, lpType, null, 1, "");

		LLVMAddClause(landingPad, llvmNull);

		// We don't care about cleanup for now.
		LLVMBuildRet(builder, LLVMConstInt(i64, 1, false));

		return fun;
	}
}

package:
auto createExecutionEngine(LLVMModuleRef dmodule) {
	char* errorPtr;
	LLVMExecutionEngineRef ee;
	if (!LLVMCreateMCJITCompilerForModule(&ee, dmodule, null, 0, &errorPtr)) {
		return ee;
	}

	scope(exit) LLVMDisposeMessage(errorPtr);

	import core.stdc.string;
	auto error = errorPtr[0 .. strlen(errorPtr)].idup;
	throw new Exception(error);
}

void destroyExecutionEngine(LLVMExecutionEngineRef ee, LLVMModuleRef dmodule) {
	char* errorPtr;
	LLVMModuleRef outMod;
	if (!LLVMRemoveModule(ee, dmodule, &outMod, &errorPtr)) {
		LLVMDisposeExecutionEngine(ee);
		return;
	}

	scope(exit) LLVMDisposeMessage(errorPtr);

	import core.stdc.string;
	auto error = errorPtr[0 .. strlen(errorPtr)].idup;
	throw new Exception(error);
}

private:

enum JitReturn {
	Direct,
	Indirect,
}

struct JitRepacker {
	CodeGen pass;
	alias pass this;

	void[] buffer;

	this(CodeGen pass, void[] buffer) {
		this.pass = pass;
		this.buffer = buffer;
	}

	import d.ir.type, d.ir.symbol;
	Constant visit(Type t) in {
		import d.llvm.type, llvm.c.target;
		auto size = LLVMStoreSizeOfType(targetData, TypeGen(pass).visit(t));

		import std.format;
		assert(
			size == buffer.length,
			format!"Buffer of length %s provided when %s was expected!"(
				buffer.length, size)
		);
	} out(result) {
		// FIXME: This does not always pass now.
		// assert(result.type == t, "Result type do not match");
		assert(buffer.length == 0, "Remaining data in the buffer!");
	} do {
		return t.accept(this);
	}

	T get(T)() {
		scope(exit) buffer = buffer[T.sizeof .. $];
		return *(cast(T*) buffer.ptr);
	}

	Constant visit(BuiltinType t) {
		ulong raw;
		switch (t) with (BuiltinType) {
			case Bool:
				return new BooleanConstant(get!bool());

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
				return new IntegerConstant(raw, t);

			default:
				assert(0, "Not implemented.");
		}
	}

	Constant visitPointerOf(Type t) {
		assert(0, "Not implemented.");
	}

	Constant visitSliceOf(Type t) {
		if (t.kind == TypeKind.Builtin && t.builtin == BuiltinType.Char
			    && t.qualifier == TypeQualifier.Immutable) {
			return new StringConstant(get!string().idup);
		}

		assert(0, "Not Implemented.");
	}

	Constant visitArrayOf(uint size, Type t) {
		import d.llvm.type, llvm.c.target;
		uint elementSize =
			cast(uint) LLVMStoreSizeOfType(targetData, TypeGen(pass).visit(t));

		Constant[] elements;
		elements.reserve(size);

		uint index = 0;

		auto x = buffer;
		scope(exit) buffer = x[index .. $];

		foreach (i; 0 .. size) {
			buffer = x[index .. index + elementSize];
			elements ~= visit(t);

			index += elementSize;
		}

		return new ArrayConstant(t, elements);
	}

	Constant visit(Struct s) {
		import d.llvm.type;
		auto type = TypeGen(pass).visit(s);

		import llvm.c.target;
		auto size = LLVMStoreSizeOfType(targetData, type);
		auto count = LLVMCountStructElementTypes(type);

		Constant[] elements;
		elements.reserve(count);

		auto x = buffer;
		scope(exit) buffer = x[size .. $];

		foreach (size_t idx, f; s.fields) {
			auto i = cast(uint) idx;
			assert(i == idx);

			assert(f.index == i, "Fields are out of order!");
			auto t = f.type;

			auto start = LLVMOffsetOfElement(targetData, type, i);
			auto elementType = LLVMStructGetTypeAtIndex(type, i);

			auto fieldSize = LLVMStoreSizeOfType(targetData, elementType);
			auto stop = start + fieldSize;

			buffer = x[start .. stop];
			elements ~= visit(t);
		}

		return new AggregateConstant(s, elements);
	}

	Constant visit(Class c) {
		assert(0, "Not Implemented.");
	}

	Constant visit(Enum e) {
		// TODO: build implicit cast.
		return visit(e.type);
	}

	Constant visit(TypeAlias a) {
		// TODO: build implicit cast.
		return visit(a.type);
	}

	Constant visit(Interface i) {
		assert(0, "Not Implemented.");
	}

	Constant visit(Union u) {
		assert(0, "Not Implemented.");
	}

	Constant visit(Function f) {
		assert(0, "Not Implemented.");
	}

	Constant visit(Type[] seq) {
		assert(0, "Not Implemented.");
	}

	Constant visit(FunctionType f) {
		assert(0, "Not Implemented.");
	}

	Constant visit(Pattern p) {
		assert(0, "Not implemented.");
	}

	import d.ir.error;
	Constant visit(CompileError e) {
		assert(0, "Not implemented.");
	}
}
