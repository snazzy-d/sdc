module d.llvm.type;

import d.llvm.codegen;

import d.ir.symbol;
import d.ir.type;

import d.exception;

import util.visitor;

import llvm.c.core;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

struct TypeGenData {
private:
	Class classInfoClass;
	
	LLVMTypeRef[Aggregate] aggTypes;
	LLVMValueRef[Aggregate] typeInfos;
	
	LLVMValueRef[Class] vtbls;
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
		ref LLVMValueRef[Class] vtbls() {
			return pass.typeGenData.vtbls;
		}
		
		@property
		ref LLVMTypeRef[Function] funCtxTypes() {
			return pass.typeGenData.funCtxTypes;
		}
	}
	
	LLVMValueRef getTypeInfo(Aggregate a) {
		if (a !in typeInfos) {
			this.dispatch(a);
		}
		
		return typeInfos[a];
	}
	
	// XXX: Remove ?
	LLVMValueRef getVtbl(Class c) {
		return vtbls[c];
	}
	
	LLVMTypeRef visit(Type t) {
		return t.getCanonical().accept(this);
	}
	
	LLVMTypeRef buildOpaque(Type t) {
		t = t.getCanonical();
		switch(t.kind) with(TypeKind) {
			case Struct:
				return buildOpaque(t.dstruct);
			
			case Union:
				return buildOpaque(t.dunion);
			
			default:
				return t.accept(this);
		}
	}
	
	LLVMTypeRef visit(BuiltinType t) {
		final switch(t) with(BuiltinType) {
			case None :
				assert(0, "Not Implemented");
			
			case Void :
				return LLVMVoidTypeInContext(llvmCtx);
			
			case Bool :
				return LLVMInt1TypeInContext(llvmCtx);
			
			case Char, Ubyte, Byte :
				return LLVMInt8TypeInContext(llvmCtx);
			
			case Wchar, Ushort, Short :
				return LLVMInt16TypeInContext(llvmCtx);
			
			case Dchar, Uint, Int :
				return LLVMInt32TypeInContext(llvmCtx);
			
			case Ulong, Long :
				return LLVMInt64TypeInContext(llvmCtx);
			
			case Ucent, Cent :
				return LLVMInt128TypeInContext(llvmCtx);
			
			case Float :
				return LLVMFloatTypeInContext(llvmCtx);
			
			case Double :
				return LLVMDoubleTypeInContext(llvmCtx);
			
			case Real :
				return LLVMX86FP80TypeInContext(llvmCtx);
			
			case Null :
				return LLVMPointerType(LLVMInt8TypeInContext(llvmCtx), 0);
		}
	}
	
	LLVMTypeRef visitPointerOf(Type t) {
		auto pointed = (t.kind != TypeKind.Builtin || t.builtin != BuiltinType.Void)
			? buildOpaque(t)
			: LLVMInt8TypeInContext(llvmCtx);
		
		return LLVMPointerType(pointed, 0);
	}
	
	LLVMTypeRef visitSliceOf(Type t) {
		LLVMTypeRef[2] types;
		types[0] = LLVMInt64TypeInContext(llvmCtx);
		types[1] = visitPointerOf(t);
		
		return LLVMStructTypeInContext(llvmCtx, types.ptr, 2, false);
	}
	
	LLVMTypeRef visitArrayOf(uint size, Type t) {
		return LLVMArrayType(visit(t), size);
	}
	
	auto buildOpaque(Struct s) {
		if (auto st = s in typeSymbols) {
			return *st;
		}
		
		return typeSymbols[s] = LLVMStructCreateNamed(
			llvmCtx,
			s.mangle.toStringz(context),
		);
	}
	
	LLVMTypeRef visit(Struct s) in {
		assert(s.step >= Step.Signed);
	} body {
		// FIXME: Ensure we don't have forward references.
		LLVMTypeRef llvmStruct = buildOpaque(s);
		if (!LLVMIsOpaqueStruct(llvmStruct)) {
			return llvmStruct;
		}
		
		LLVMTypeRef[] types;
		foreach(member; s.members) {
			if (auto f = cast(Field) member) {
				types ~= visit(f.type);
			}
		}
		
		LLVMStructSetBody(llvmStruct, types.ptr, cast(uint) types.length, false);
		return llvmStruct;
	}
	
	auto buildOpaque(Union u) {
		if (auto ut = u in typeSymbols) {
			return *ut;
		}
		
		return typeSymbols[u] = LLVMStructCreateNamed(
			llvmCtx,
			u.mangle.toStringz(context),
		);
	}
	
	LLVMTypeRef visit(Union u) in {
		assert(u.step >= Step.Signed);
	} body {
		// FIXME: Ensure we don't have forward references.
		LLVMTypeRef llvmStruct = buildOpaque(u);
		if (!LLVMIsOpaqueStruct(llvmStruct)) {
			return llvmStruct;
		}
		
		auto hasContext = u.hasContext;
		auto members = u.members;
		assert(!hasContext, "Voldemort union not supported atm");
		
		LLVMTypeRef[3] types;
		uint elementCount = 1 + hasContext;
		
		uint firstindex, size, dalign;
		foreach(i, m; members) {
			if (auto f = cast(Field) m) {
				types[hasContext] = visit(f.type);
				
				import llvm.c.target;
				size = cast(uint) LLVMStoreSizeOfType(targetData, types[hasContext]);
				dalign = cast(uint) LLVMABIAlignmentOfType(targetData, types[hasContext]);
				
				firstindex = cast(uint) (i + 1);
				break;
			}
		}
		
		uint extra;
		foreach(m; members[firstindex .. $]) {
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
		assert(
			LLVMABIAlignmentOfType(targetData, llvmStruct) == dalign,
			"union with differing alignement are not supported."
		);
		
		return llvmStruct;
	}
	
	LLVMTypeRef visit(Class c) {
		// Ensure classInfo is built first.
		if (!classInfoClass) {
			classInfoClass = pass.object.getClassInfo();
			
			if (c !is classInfoClass) {
				visit(classInfoClass);
			}
		}
		
		if (auto ct = c in typeSymbols) {
			return *ct;
		}
		
		auto mangle = c.mangle.toString(context);
		auto llvmStruct = LLVMStructCreateNamed(llvmCtx, mangle.ptr);
		auto structPtr = typeSymbols[c] = LLVMPointerType(llvmStruct, 0);
		
		import std.string;
		auto classInfoPtr = visit(classInfoClass);
		auto classInfoStruct = LLVMGetElementType(classInfoPtr);
		auto vtblStruct = LLVMStructCreateNamed(llvmCtx, toStringz(mangle ~ "__vtbl"));
		auto vtblPtr = LLVMPointerType(vtblStruct, 0);
		
		LLVMTypeRef[2] classDataElts = [classInfoStruct, vtblStruct];
		auto classDataStruct = LLVMStructTypeInContext(
			llvmCtx,
			classDataElts.ptr,
			cast(uint) classDataElts.length,
			false,
		);
		
		import std.string;
		auto classData = LLVMAddGlobal(
			dmodule,
			classDataStruct,
			toStringz(mangle ~ "__Metadata"),
		);
		
		typeInfos[c] = LLVMConstBitCast(classData, classInfoPtr);
		
		LLVMValueRef[] methods;
		LLVMTypeRef[] initTypes = [vtblPtr];
		foreach(member; c.members) {
			if (auto m = cast(Method) member) {
				auto oldBody = m.fbody;
				scope(exit) m.fbody = oldBody;
				// FIXME: Do whatever is needed here.
				// m.fbody = null;
				
				import d.llvm.global;
				methods ~= GlobalGen(pass).declare(m);
			} else if (auto f = cast(Field) member) {
				if (f.index > 0) {
					initTypes ~= visit(f.value.type);
				}
			}
		}
		
		LLVMStructSetBody(
			llvmStruct,
			initTypes.ptr,
			cast(uint) initTypes.length,
			false,
		);
		
		import std.algorithm, std.array;
		auto vtblTypes = methods.map!(m => LLVMTypeOf(m)).array();
		LLVMStructSetBody(
			vtblStruct,
			vtblTypes.ptr,
			cast(uint) vtblTypes.length,
			false,
		);
		
		auto vtbl = LLVMConstNamedStruct(
			vtblStruct,
			methods.ptr,
			cast(uint) methods.length,
		);
		
		auto i32 = LLVMInt32TypeInContext(llvmCtx);
		LLVMValueRef[2] indices = [
			LLVMConstInt(i32, 0, false),
			LLVMConstInt(i32, 1, false),
		];
		
		vtbls[c] = LLVMConstInBoundsGEP(
			classData,
			indices.ptr,
			indices.length,
		);
		
		// Doing it at the end to avoid infinite recursion
		// when generating object.ClassInfo
		auto base = c.base;
		visit(base);
		
		LLVMValueRef[2] classInfoData = [getVtbl(classInfoClass), getTypeInfo(base)];
		auto classInfoGen = LLVMConstNamedStruct(
			classInfoStruct,
			classInfoData.ptr,
			classInfoData.length,
		);
		
		LLVMValueRef[2] classDataData = [classInfoGen, vtbl];
		auto classDataGen = LLVMConstNamedStruct(
			classDataStruct,
			classDataData.ptr,
			classDataData.length,
		);
		
		LLVMSetInitializer(classData, classDataGen);
		LLVMSetGlobalConstant(classData, true);
		LLVMSetLinkage(classData, LLVMLinkage.LinkOnceODR);
		
		return structPtr;
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
		auto llvmStruct = typeSymbols[i] = LLVMStructCreateNamed(llvmCtx, mangle.ptr);
		
		import std.string;
		auto vtblStruct = LLVMStructCreateNamed(llvmCtx, toStringz(mangle ~ "__vtbl"));
		LLVMTypeRef[2] elements;
		elements[0] = visit(pass.object.getObject());
		elements[1] = LLVMPointerType(vtblStruct, 0);
		LLVMStructSetBody(llvmStruct, elements.ptr, elements.length, false);
		return llvmStruct;
	}
	
	LLVMTypeRef visit(Function f) in {
		assert(f.step >= Step.Signed);
	} body {
		return funCtxTypes.get(f, {
			auto count = cast(uint) f.closure.length + f.hasContext;
			
			import std.string;
			auto ctxStruct = funCtxTypes[f] = LLVMStructCreateNamed(
				pass.llvmCtx,
				toStringz("S" ~ f.mangle.toString(pass.context)[2 .. $] ~ ".ctx"),
			);
			
			LLVMTypeRef[] ctxElts;
			ctxElts.length = count;
			
			if (f.hasContext) {
				auto parentCtxType = f.type.parameters[0].getType();
				ctxElts[0] = LLVMPointerType(visit(parentCtxType), 0);
			}
			
			foreach(v, i; f.closure) {
				ctxElts[i] = visit(v.type);
			}
			
			LLVMStructSetBody(ctxStruct, ctxElts.ptr, count, false);
			return ctxStruct;
		}());
	}
	
	private auto buildParamType(ParamType pt) {
		auto t = visit(pt.getType());
		if (pt.isRef) {
			t = LLVMPointerType(t, 0);
		}
		
		return t;
	}
	
	LLVMTypeRef visit(FunctionType f) {
		import std.algorithm, std.array;
		auto params = f.getFunction().parameters.map!(p => buildParamType(p)).array();
		auto fun = LLVMPointerType(LLVMFunctionType(
			buildParamType(f.returnType),
			params.ptr,
			cast(uint) params.length,
			f.isVariadic,
		), 0);
		
		auto contexts = f.contexts;
		if (contexts.length == 0) {
			return fun;
		}
		
		auto length = cast(uint) contexts.length;
		
		LLVMTypeRef[] types;
		types.length = length + 1;
		
		foreach(i, _; contexts) {
			types[i] = params[i];
		}
		
		types[length] = fun;
		return LLVMStructTypeInContext(llvmCtx, types.ptr, length + 1, false);
	}
	
	LLVMTypeRef visit(Type[] seq) {
		import std.algorithm, std.array;
		auto types = seq.map!(t => visit(t)).array();
		return LLVMStructTypeInContext(llvmCtx, types.ptr, cast(uint) types.length, false);
	}
	
	LLVMTypeRef visit(TypeTemplateParameter p) {
		assert(0, "Template type can't be generated.");
	}
	
	import d.ir.error;
	LLVMTypeRef visit(CompileError e) {
		assert(0, "Error type can't be generated.");
	}
}
