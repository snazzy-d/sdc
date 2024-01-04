module d.llvm.type;

import d.llvm.codegen;

import d.ir.symbol;
import d.ir.type;

import source.exception;

import util.visitor;

import llvm.c.core;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct TypeGenData {
private:
	LLVMTypeRef[Aggregate] aggTypes;
	LLVMTypeRef[Function] funCtxTypes;
}

struct TypeGen {
	private CodeGen pass;
	alias pass this;

	this(CodeGen pass) {
		this.pass = pass;
	}

	// XXX: lack of multiple alias this, so we do it automanually.
	private {
		@property
		ref LLVMTypeRef[Aggregate] typeSymbols() {
			return pass.typeGenData.aggTypes;
		}

		@property
		ref LLVMTypeRef[Function] funCtxTypes() {
			return pass.typeGenData.funCtxTypes;
		}
	}

	LLVMTypeRef visit(Type t) {
		return t.getCanonical().accept(this);
	}

	LLVMTypeRef buildOpaque(Type t) {
		t = t.getCanonical();
		switch (t.kind) with (TypeKind) {
			case Struct:
				return buildOpaque(t.dstruct);

			case Union:
				return buildOpaque(t.dunion);

			case Context:
				return buildOpaque(t.context);

			default:
				return t.accept(this);
		}
	}

	LLVMTypeRef visit(BuiltinType t) {
		final switch (t) with (BuiltinType) {
			case None:
				assert(0, "Not Implemented");

			case Void:
				return llvmVoid;

			case Bool:
				return i1;

			case Char, Ubyte, Byte:
				return i8;

			case Wchar, Ushort, Short:
				return i16;

			case Dchar, Uint, Int:
				return i32;

			case Ulong, Long:
				return i64;

			case Ucent, Cent:
				return i128;

			case Float:
				return LLVMFloatTypeInContext(llvmCtx);

			case Double:
				return LLVMDoubleTypeInContext(llvmCtx);

			case Real:
				return LLVMX86FP80TypeInContext(llvmCtx);

			case Null:
				return llvmPtr;
		}
	}

	LLVMTypeRef getElementType(Type t) {
		t = t.getCanonical().element.getCanonical();
		if (t.kind == TypeKind.Builtin && t.builtin == BuiltinType.Void) {
			// void* is represented as i8* in LLVM IR.
			return i8;
		}

		return buildOpaque(t);
	}

	LLVMTypeRef visitPointerOf(Type t) {
		return llvmPtr;
	}

	LLVMTypeRef visitSliceOf(Type t) {
		return llvmSlice;
	}

	LLVMTypeRef visitArrayOf(uint size, Type t) {
		return LLVMArrayType(visit(t), size);
	}

	auto buildOpaque(Struct s) {
		if (auto st = s in typeSymbols) {
			return *st;
		}

		return typeSymbols[s] =
			LLVMStructCreateNamed(llvmCtx, s.mangle.toStringz(context));
	}

	LLVMTypeRef visit(Struct s) in(s.step >= Step.Signed) {
		// FIXME: Ensure we don't have forward references.
		auto llvmStruct = buildOpaque(s);
		if (!LLVMIsOpaqueStruct(llvmStruct)) {
			return llvmStruct;
		}

		import std.algorithm, std.array;
		auto types = s.fields.map!(f => visit(f.type)).array();

		LLVMStructSetBody(llvmStruct, types.ptr, cast(uint) types.length,
		                  false);
		return llvmStruct;
	}

	auto buildOpaque(Union u) {
		if (auto ut = u in typeSymbols) {
			return *ut;
		}

		return typeSymbols[u] =
			LLVMStructCreateNamed(llvmCtx, u.mangle.toStringz(context));
	}

	LLVMTypeRef visit(Union u) in(u.step >= Step.Signed) {
		// FIXME: Ensure we don't have forward references.
		auto llvmStruct = buildOpaque(u);
		if (!LLVMIsOpaqueStruct(llvmStruct)) {
			return llvmStruct;
		}

		auto hasContext = u.hasContext;
		assert(!hasContext, "Voldemort union not supported atm");

		auto fields = u.fields;
		bool hasFields = fields.length != 0;

		LLVMTypeRef[3] types;
		uint elementCount = 1 + hasContext;

		uint size, dalign;
		if (hasFields) {
			types[hasContext] = visit(fields[0].type);

			import llvm.c.target;
			size =
				cast(uint) LLVMStoreSizeOfType(targetData, types[hasContext]);
			dalign = cast(uint)
				LLVMABIAlignmentOfType(targetData, types[hasContext]);
		}

		uint extra;
		foreach (f; fields[hasFields .. $]) {
			auto t = visit(f.type);

			import llvm.c.target;
			auto s = cast(uint) LLVMStoreSizeOfType(targetData, t);
			auto a = cast(uint) LLVMABIAlignmentOfType(targetData, t);

			extra = ((size + extra) < s) ? s - size : extra;
			dalign = (a > dalign) ? a : dalign;
		}

		if (extra > 0) {
			elementCount++;
			types[1] = LLVMArrayType(i8, extra);
		}

		LLVMStructSetBody(llvmStruct, types.ptr, elementCount, false);

		import llvm.c.target;
		assert(LLVMABIAlignmentOfType(targetData, llvmStruct) == dalign,
		       "union with differing alignement are not supported.");

		return llvmStruct;
	}

	LLVMTypeRef getClassStructure(Class c) in(c.step >= Step.Signed) {
		// We do so after generating ClassInfo in case
		// we are generating a base of ClassInfo.
		if (auto ct = c in typeSymbols) {
			return *ct;
		}

		auto mangle = c.mangle.toString(context);
		auto classBody =
			typeSymbols[c] = LLVMStructCreateNamed(llvmCtx, mangle.ptr);

		LLVMTypeRef[] initTypes = [llvmPtr];
		foreach (f; c.fields[1 .. $]) {
			initTypes ~= visit(f.value.type);
		}

		LLVMStructSetBody(classBody, initTypes.ptr, cast(uint) initTypes.length,
		                  false);
		return classBody;
	}

	LLVMTypeRef visit(Class c) {
		return llvmPtr;
	}

	LLVMTypeRef visit(Enum e) {
		return visit(e.type);
	}

	LLVMTypeRef visit(TypeAlias a) {
		assert(0, "Use getCanonical");
	}

	LLVMTypeRef visit(Interface i) {
		if (auto it = i in typeSymbols) {
			return *it;
		}

		auto mangle = i.mangle.toString(context);
		auto llvmStruct =
			typeSymbols[i] = LLVMStructCreateNamed(llvmCtx, mangle.ptr);

		LLVMTypeRef[2] elements = [llvmPtr, llvmPtr];
		LLVMStructSetBody(llvmStruct, elements.ptr, elements.length, false);

		return llvmStruct;
	}

	auto buildOpaque(Function f) {
		if (auto fctx = f in funCtxTypes) {
			return *fctx;
		}

		import std.string;
		return funCtxTypes[f] = LLVMStructCreateNamed(
			llvmCtx, toStringz("S" ~ f.name.toString(context) ~ ".ctx"));
	}

	LLVMTypeRef visit(Function f)
			in(f.step >= Step.Processed,
			   f.name.toString(pass.context) ~ " isn't signed") {
		auto ctxStruct = buildOpaque(f);
		if (!LLVMIsOpaqueStruct(ctxStruct)) {
			return ctxStruct;
		}

		auto count = cast(uint) f.closure.length + f.hasContext;

		LLVMTypeRef[] ctxElts;
		ctxElts.length = count;

		if (f.hasContext) {
			ctxElts[0] = llvmPtr;
		}

		foreach (v, i; f.closure) {
			ctxElts[i] = visit(v.type);
		}

		LLVMStructSetBody(ctxStruct, ctxElts.ptr, count, false);
		return ctxStruct;
	}

	private auto buildParamType(ParamType pt) {
		return pt.isRef ? llvmPtr : visit(pt.getType());
	}

	LLVMTypeRef getFunctionType(FunctionType f) {
		import std.algorithm, std.array;
		auto params =
			f.getFunction().parameters.map!(p => buildParamType(p)).array();
		return LLVMFunctionType(buildParamType(f.returnType), params.ptr,
		                        cast(uint) params.length, f.isVariadic);
	}

	LLVMTypeRef visit(FunctionType f) {
		auto contexts = f.contexts;
		if (contexts.length == 0) {
			// XXX: This seems inconsistent with the case that
			// contains contexts. Maybe a 1 element struct would
			// be more apropriate?
			return llvmPtr;
		}

		auto length = cast(uint) contexts.length;

		LLVMTypeRef[] types;
		types.length = length + 1;

		foreach (i, _; contexts) {
			// XXX: That's a bit redundant, but will work.
			types[i] = buildParamType(f.getFunction().parameters[i]);
		}

		types[length] = llvmPtr;
		return LLVMStructTypeInContext(llvmCtx, types.ptr, length + 1, false);
	}

	LLVMTypeRef visit(Type[] splat) {
		import std.algorithm, std.array;
		auto types = splat.map!(t => visit(t)).array();
		return LLVMStructTypeInContext(llvmCtx, types.ptr,
		                               cast(uint) types.length, false);
	}

	LLVMTypeRef visit(Pattern p) {
		assert(0, "Patterns cannot be generated.");
	}

	import d.ir.error;
	LLVMTypeRef visit(CompileError e) {
		assert(0, "Error type can't be generated.");
	}
}
