module d.llvm.type;

import d.llvm.codegen;

import d.ir.symbol;
import d.ir.type;

import d.exception;

import util.visitor;

import llvm.c.core;

import std.algorithm;
import std.array;
import std.string;

// Conflict with Interface in object.di
alias Interface = d.ir.symbol.Interface;

final class TypeGen {
	private CodeGenPass pass;
	alias pass this;
	
	private LLVMTypeRef[TypeSymbol] typeSymbols;
	private LLVMValueRef[TypeSymbol] typeInfos;
	
	private LLVMValueRef[Class] vtbls;
	private LLVMTypeRef[Function] funCtxTypes;
	
	private Class classInfoClass;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMValueRef getTypeInfo(TypeSymbol s) {
		return typeInfos[s];
	}
	
	LLVMTypeRef visit(Type t) {
		return t.accept(this);
	}
	
	LLVMTypeRef visit(BuiltinType t) {
		final switch(t) with(BuiltinType) {
			case None :
				assert(0, "Not Implemented");
			
			case Void :
				return LLVMVoidTypeInContext(llvmCtx);
			
			case Bool :
				return LLVMInt1TypeInContext(llvmCtx);
			
			case Char :
			case Ubyte :
			case Byte :
				return LLVMInt8TypeInContext(llvmCtx);
			
			case Wchar :
			case Ushort :
			case Short :
				return LLVMInt16TypeInContext(llvmCtx);
			
			case Dchar :
			case Uint :
			case Int :
				return LLVMInt32TypeInContext(llvmCtx);
			
			case Ulong :
			case Long :
				return LLVMInt64TypeInContext(llvmCtx);
			
			case Ucent :
			case Cent :
				return LLVMIntTypeInContext(llvmCtx, 128);
			
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
			? visit(t)
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
	
	LLVMTypeRef visit(Struct s) {
		if (auto st = s in typeSymbols) {
			return *st;
		}
		
		auto llvmStruct = typeSymbols[s] = LLVMStructCreateNamed(llvmCtx, cast(char*) s.mangle.toStringz());
		
		LLVMTypeRef[] types;
		foreach(member; s.members) {
			if(auto f = cast(Field) member) {
				types ~= visit(f.type);
			}
		}
		
		LLVMStructSetBody(llvmStruct, types.ptr, cast(uint) types.length, false);
		return llvmStruct;
	}
	
	LLVMTypeRef visit(Class c) {
		// Ensure classInfo is built first.
		if(!classInfoClass) {
			classInfoClass = pass.object.getClassInfo();
			
			if(c !is classInfoClass) {
				visit(classInfoClass);
			}
		}
		
		if (auto ct = c in typeSymbols) {
			return *ct;
		}
		
		auto llvmStruct = LLVMStructCreateNamed(llvmCtx, cast(char*) c.mangle.toStringz());
		auto structPtr = typeSymbols[c] = LLVMPointerType(llvmStruct, 0);
		
		auto classInfoStruct = LLVMGetElementType(visit(classInfoClass));
		auto classInfo = LLVMAddGlobal(dmodule, classInfoStruct, cast(char*) (c.mangle ~ "__ClassInfo").toStringz());
		LLVMSetGlobalConstant(classInfo, true);
		LLVMSetLinkage(classInfo, LLVMLinkage.LinkOnceODR);
		
		typeInfos[c] = classInfo;
		
		auto vtbl = [classInfo];
		LLVMValueRef[] fields = [null];
		foreach(member; c.members) {
			if (auto m = cast(Method) member) {
				auto oldBody = m.fbody;
				scope(exit) m.fbody = oldBody;
				
				m.fbody = null;
				vtbl ~= pass.visit(m);
			} else if(auto f = cast(Field) member) {
				if(f.index > 0) {
					import d.llvm.expression;
					fields ~= ExpressionGen(pass).visit(f.value);
				}
			}
		}
		
		auto vtblTypes = vtbl.map!(m => LLVMTypeOf(m)).array();
		auto vtblStruct = LLVMStructCreateNamed(llvmCtx, cast(char*) (c.mangle ~ "__vtbl").toStringz());
		LLVMStructSetBody(vtblStruct, vtblTypes.ptr, cast(uint) vtblTypes.length, false);
		
		auto vtblPtr = LLVMAddGlobal(dmodule, vtblStruct, (c.mangle ~ "__vtblZ").toStringz());
		LLVMSetInitializer(vtblPtr, LLVMConstNamedStruct(vtblStruct, vtbl.ptr, cast(uint) vtbl.length));
		LLVMSetGlobalConstant(vtblPtr, true);
		LLVMSetLinkage(vtblPtr, LLVMLinkage.LinkOnceODR);
		
		// Set vtbl.
		vtbls[c] = fields[0] = vtblPtr;
		auto initTypes = fields.map!(f => LLVMTypeOf(f)).array();
		LLVMStructSetBody(llvmStruct, initTypes.ptr, cast(uint) initTypes.length, false);
		
		// Doing it at the end to avoid infinite recursion when generating object.ClassInfo
		auto base = c.base;
		visit(base);
		
		LLVMValueRef[2] classInfoData = [getVtbl(classInfoClass), getTypeInfo(base)];
		LLVMSetInitializer(classInfo, LLVMConstNamedStruct(classInfoStruct, classInfoData.ptr, 2));
		
		return structPtr;
	}
	
	LLVMValueRef getVtbl(Class c) {
		return vtbls[c];
	}
	
	LLVMTypeRef visit(Enum e) {
		if (auto et = e in typeSymbols) {
			return *et;
		}
		
		return typeSymbols[e] = visit(e.type);
	}
	
	LLVMTypeRef visit(TypeAlias a) {
		return visit(a.type);
	}
	
	LLVMTypeRef visit(Interface i) {
		assert(0, "codegen for interface is not implemented.");
	}
	
	LLVMTypeRef visit(Union u) {
		assert(0, "codegen for interface is not implemented.");
	}
	
	LLVMTypeRef visit(Function f) {
		return funCtxTypes.get(f, {
			return funCtxTypes[f] = LLVMStructCreateNamed(pass.llvmCtx, ("S" ~ f.mangle[2 .. $] ~ ".ctx").toStringz());
		}());
	}

	private auto buildParamType(ParamType pt) {
		auto t = visit(pt.getType());
		if(pt.isRef) {
			t = LLVMPointerType(t, 0);
		}
		
		return t;
	}
	
	LLVMTypeRef visit(FunctionType f) {
		auto params = f.getDelegate(0).parameters.map!(p => buildParamType(p)).array();
		auto fun = LLVMPointerType(LLVMFunctionType(buildParamType(f.returnType), params.ptr, cast(uint) params.length, f.isVariadic), 0);
		
		auto contexts = f.contexts;
		if (contexts.length == 0) {
			return fun;
		}
		
		assert(contexts.length == 1, "Multiple contexts not implemented.");
		
		LLVMTypeRef[2] types;
		types[0] = fun;
		types[1] = params[0];
		
		return LLVMStructTypeInContext(llvmCtx, types.ptr, 2, false);
	}
	
	LLVMTypeRef visit(Type[] seq) {
		auto types = seq.map!(t => visit(t)).array();
		return LLVMStructTypeInContext(llvmCtx, types.ptr, cast(uint) types.length, false);
	}
	
	LLVMTypeRef visit(TypeTemplateParameter p) {
		assert(0, "Template type can't be generated.");
	}
}

