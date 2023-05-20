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
	Class classInfoClass;

	LLVMTypeRef[Aggregate] aggTypes;
	LLVMValueRef[Aggregate] typeInfos;

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
		ref Class classInfoClass() {
			return pass.typeGenData.classInfoClass;
		}

		@property
		ref LLVMTypeRef[Aggregate] typeSymbols() {
			return pass.typeGenData.aggTypes;
		}

		@property
		ref LLVMValueRef[Aggregate] typeInfos() {
			return pass.typeGenData.typeInfos;
		}

		@property
		ref LLVMTypeRef[Function] funCtxTypes() {
			return pass.typeGenData.funCtxTypes;
		}
	}

	LLVMValueRef getTypeInfo(A : Aggregate)(A a) {
		if (a !in typeInfos) {
			this.dispatch(a);
		}

		return typeInfos[a];
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
				return LLVMVoidTypeInContext(llvmCtx);

			case Bool:
				return LLVMInt1TypeInContext(llvmCtx);

			case Char, Ubyte, Byte:
				return LLVMInt8TypeInContext(llvmCtx);

			case Wchar, Ushort, Short:
				return LLVMInt16TypeInContext(llvmCtx);

			case Dchar, Uint, Int:
				return LLVMInt32TypeInContext(llvmCtx);

			case Ulong, Long:
				return LLVMInt64TypeInContext(llvmCtx);

			case Ucent, Cent:
				return LLVMInt128TypeInContext(llvmCtx);

			case Float:
				return LLVMFloatTypeInContext(llvmCtx);

			case Double:
				return LLVMDoubleTypeInContext(llvmCtx);

			case Real:
				return LLVMX86FP80TypeInContext(llvmCtx);

			case Null:
				return LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0);
		}
	}

	private LLVMTypeRef genPointee(Type t) {
		t = t.getCanonical();
		if (t.kind == TypeKind.Builtin && t.builtin == BuiltinType.Void) {
			// void* is represented as i8* in LLVM IR.
			return LLVMInt8TypeInContext(llvmCtx);
		}

		return buildOpaque(t);
	}

	LLVMTypeRef getElementType(Type t) {
		return genPointee(t.getCanonical().element);
	}

	LLVMTypeRef visitPointerOf(Type t) {
		return LLVMPointerType(genPointee(t), 0);
	}

	LLVMTypeRef visitSliceOf(Type t) {
		LLVMTypeRef[2] types =
			[LLVMInt64TypeInContext(llvmCtx), visitPointerOf(t)];

		return LLVMStructTypeInContext(llvmCtx, types.ptr, types.length, false);
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

		LLVMTypeRef[] types;
		foreach (member; s.members) {
			if (auto f = cast(Field) member) {
				types ~= visit(f.type);
			}
		}

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
		auto members = u.members;
		assert(!hasContext, "Voldemort union not supported atm");

		LLVMTypeRef[3] types;
		uint elementCount = 1 + hasContext;

		uint firstindex, size, dalign;
		foreach (i, m; members) {
			if (auto f = cast(Field) m) {
				types[hasContext] = visit(f.type);

				import llvm.c.target;
				size = cast(uint)
					LLVMStoreSizeOfType(targetData, types[hasContext]);
				dalign = cast(uint)
					LLVMABIAlignmentOfType(targetData, types[hasContext]);

				firstindex = cast(uint) (i + 1);
				break;
			}
		}

		uint extra;
		foreach (m; members[firstindex .. $]) {
			if (auto f = cast(Field) m) {
				auto t = visit(f.type);

				import llvm.c.target;
				auto s = cast(uint) LLVMStoreSizeOfType(targetData, t);
				auto a = cast(uint) LLVMABIAlignmentOfType(targetData, t);

				extra = ((size + extra) < s) ? s - size : extra;
				dalign = (a > dalign) ? a : dalign;
			}
		}

		if (extra > 0) {
			elementCount++;
			types[1] = LLVMArrayType(LLVMInt8TypeInContext(llvmCtx), extra);
		}

		LLVMStructSetBody(llvmStruct, types.ptr, elementCount, false);

		import llvm.c.target;
		assert(LLVMABIAlignmentOfType(targetData, llvmStruct) == dalign,
		       "union with differing alignement are not supported.");

		return llvmStruct;
	}

	private LLVMValueRef genPrimaries(Class c, string mangle,
	                                  LLVMTypeRef classInfoPtr) {
		auto count = cast(uint) c.primaries.length;
		auto sizeType =
			LLVMConstInt(LLVMInt64TypeInContext(llvmCtx), count, false);

		if (count == 0) {
			LLVMValueRef[2] elts =
				[sizeType, LLVMConstNull(LLVMPointerType(classInfoPtr, 0))];
			return
				LLVMConstStructInContext(llvmCtx, elts.ptr, elts.length, false);
		}

		auto type = LLVMArrayType(classInfoPtr, count);

		import std.algorithm, std.array;
		auto parents = c.primaries.map!(p => getTypeInfo(p)).array();
		auto gen = LLVMConstArray(classInfoPtr, parents.ptr, count);

		import std.string;
		auto primaries =
			LLVMAddGlobal(dmodule, type, toStringz(mangle ~ "__primaries"));
		LLVMSetInitializer(primaries, gen);
		LLVMSetGlobalConstant(primaries, true);
		LLVMSetUnnamedAddr(primaries, true);
		LLVMSetLinkage(primaries, LLVMLinkage.LinkOnceODR);

		LLVMValueRef[2] elts = [sizeType, primaries];
		return LLVMConstStructInContext(llvmCtx, elts.ptr, elts.length, false);
	}

	LLVMTypeRef getClassInfoStructure() {
		if (!classInfoClass) {
			classInfoClass = pass.object.getClassInfo();
		}

		return getClassStructure(classInfoClass);
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

		import std.string;
		auto metadataStruct =
			LLVMStructCreateNamed(llvmCtx, toStringz(mangle ~ "__metadata"));
		auto metadata = LLVMAddGlobal(dmodule, metadataStruct,
		                              toStringz(mangle ~ "__vtbl"));

		auto classInfoStruct = getClassInfoStructure();
		auto classInfoPtr = LLVMPointerType(classInfoStruct, 0);
		typeInfos[c] = LLVMConstBitCast(metadata, classInfoPtr);
		auto metadataPtr = LLVMPointerType(metadataStruct, 0);

		LLVMValueRef[] methods;
		LLVMTypeRef[] initTypes = [metadataPtr];
		foreach (member; c.members) {
			if (auto m = cast(Method) member) {
				import d.llvm.global;
				methods ~= GlobalGen(pass).declare(m);
				continue;
			}

			if (auto f = cast(Field) member) {
				if (f.index > 0) {
					initTypes ~= visit(f.value.type);
				}
			}
		}

		LLVMStructSetBody(classBody, initTypes.ptr, cast(uint) initTypes.length,
		                  false);

		import std.algorithm, std.array;
		auto vtblTypes = methods.map!(m => LLVMTypeOf(m)).array();
		auto vtblStruct =
			LLVMStructTypeInContext(llvmCtx, vtblTypes.ptr,
			                        cast(uint) vtblTypes.length, false);

		LLVMTypeRef[2] classMetadataElts = [classInfoStruct, vtblStruct];
		LLVMStructSetBody(metadataStruct, classMetadataElts.ptr,
		                  classMetadataElts.length, false);

		auto vtbl = LLVMConstStructInContext(llvmCtx, methods.ptr,
		                                     cast(uint) methods.length, false);

		LLVMValueRef[2] classInfoData = [getTypeInfo(classInfoClass),
		                                 genPrimaries(c, mangle, classInfoPtr)];
		auto classInfoGen =
			LLVMConstNamedStruct(classInfoStruct, classInfoData.ptr,
			                     classInfoData.length);

		LLVMValueRef[2] classDataData = [classInfoGen, vtbl];
		auto metadataGen =
			LLVMConstNamedStruct(metadataStruct, classDataData.ptr,
			                     classDataData.length);

		LLVMSetInitializer(metadata, metadataGen);
		LLVMSetGlobalConstant(metadata, true);
		LLVMSetLinkage(metadata, LLVMLinkage.LinkOnceODR);

		return classBody;
	}

	LLVMTypeRef visit(Class c) {
		auto classBody = getClassStructure(c);
		return LLVMPointerType(classBody, 0);
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

		import std.string;
		auto vtblStruct =
			LLVMStructCreateNamed(llvmCtx, toStringz(mangle ~ "__vtbl"));

		LLVMTypeRef[2] elements =
			[visit(pass.object.getObject()), LLVMPointerType(vtblStruct, 0)];
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
			auto parentCtxType = f.type.parameters[0].getType();
			ctxElts[0] = LLVMPointerType(visit(parentCtxType), 0);
		}

		foreach (v, i; f.closure) {
			ctxElts[i] = visit(v.type);
		}

		LLVMStructSetBody(ctxStruct, ctxElts.ptr, count, false);
		return ctxStruct;
	}

	private auto buildParamType(ParamType pt) {
		auto t = visit(pt.getType());
		if (pt.isRef) {
			t = LLVMPointerType(t, 0);
		}

		return t;
	}

	LLVMTypeRef getFunctionType(FunctionType f) {
		import std.algorithm, std.array;
		auto params =
			f.getFunction().parameters.map!(p => buildParamType(p)).array();
		return LLVMFunctionType(buildParamType(f.returnType), params.ptr,
		                        cast(uint) params.length, f.isVariadic);
	}

	LLVMTypeRef visit(FunctionType f) {
		auto fun = getFunctionType(f);
		auto funPtr = LLVMPointerType(fun, 0);

		auto contexts = f.contexts;
		if (contexts.length == 0) {
			// XXX: This seems inconsistent with the case that
			// contains contexts. Maybe a 1 element struct would
			// be more apropriate?
			return funPtr;
		}

		auto length = cast(uint) contexts.length;

		LLVMTypeRef[] types;
		types.length = length + 1;

		foreach (i, _; contexts) {
			// XXX: That's a bit redundant, but will work.
			types[i] = buildParamType(f.getFunction().parameters[i]);
		}

		types[length] = funPtr;
		return LLVMStructTypeInContext(llvmCtx, types.ptr, length + 1, false);
	}

	LLVMTypeRef visit(Type[] seq) {
		import std.algorithm, std.array;
		auto types = seq.map!(t => visit(t)).array();
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
