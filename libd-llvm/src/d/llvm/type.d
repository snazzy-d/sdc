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

final class TypeGen {
	private CodeGenPass pass;
	alias pass this;
	
	private LLVMTypeRef[TypeSymbol] typeSymbols;
	private LLVMValueRef[TypeSymbol] newInits;
	private LLVMValueRef[TypeSymbol] typeInfos;
	
	private Class classInfoClass;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMValueRef getNewInit(TypeSymbol s) {
		return newInits[s];
	}
	
	LLVMValueRef getTypeInfo(TypeSymbol s) {
		return typeInfos[s];
	}
	
	LLVMTypeRef visit(QualType t) {
		return visit(t.type);
	}
	
	LLVMTypeRef visit(Type t) {
		return this.dispatch!(function LLVMTypeRef(Type t) {
			assert(0, typeid(t).toString() ~ " is not supported");
		})(t);
	}
	
	LLVMTypeRef visit(AliasType t) {
		return visit(t.dalias.type);
	}
	
	LLVMTypeRef visit(StructType t) {
		auto s = t.dstruct;
		
		if (auto st = s in typeSymbols) {
			return *st;
		}
		
		auto llvmStruct = typeSymbols[s] = LLVMStructCreateNamed(llvmCtx, cast(char*) s.mangle.toStringz());
		
		LLVMTypeRef[] types;
		foreach(member; s.members) {
			if(auto f = cast(Field) member) {
				types ~= pass.visit(f.type);
			}
		}
		
		LLVMStructSetBody(llvmStruct, types.ptr, cast(uint) types.length, false);
		
		import d.context;
		auto init = cast(Variable) s.dscope.resolve(BuiltinName!"init");
		assert(init);
		
		newInits[s] = pass.visit(init);
		
		return llvmStruct;
	}
	
	LLVMTypeRef visit(ClassType t) {
		return buildClass(t.dclass);
	}
	
	LLVMTypeRef buildClass(Class c) {
		// Ensure classInfo is built first.
		if(!classInfoClass) {
			classInfoClass = pass.object.getClassInfo();
			
			if(c !is classInfoClass) {
				buildClass(classInfoClass);
			}
		}
		
		if (auto ct = c in typeSymbols) {
			return *ct;
		}
		
		auto llvmStruct = LLVMStructCreateNamed(llvmCtx, cast(char*) c.mangle.toStringz());
		auto structPtr = typeSymbols[c] = LLVMPointerType(llvmStruct, 0);
		
		auto classInfo = LLVMAddGlobal(dmodule, LLVMGetElementType(buildClass(classInfoClass)), cast(char*) (c.mangle ~ "__ClassInfo").toStringz());
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
					fields ~= pass.visit(f.value);
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
		fields[0] = vtblPtr;
		auto initTypes = fields.map!(f => LLVMTypeOf(f)).array();
		LLVMStructSetBody(llvmStruct, initTypes.ptr, cast(uint) initTypes.length, false);
		
		auto initPtr = LLVMAddGlobal(dmodule, llvmStruct, (c.mangle ~ "__initZ").toStringz());
		LLVMSetInitializer(initPtr, LLVMConstNamedStruct(llvmStruct, fields.ptr, cast(uint) fields.length));
		LLVMSetGlobalConstant(initPtr, true);
		LLVMSetLinkage(initPtr, LLVMLinkage.LinkOnceODR);
		
		newInits[c] = initPtr;
		
		// Doing it at the end to avoid infinite recursion when generating object.ClassInfo
		// Also, we may want to do that in symbol and generate with the class.
		auto base = c.base;
		buildClass(base);
		auto classInfoData = LLVMGetInitializer(getNewInit(classInfoClass));
		uint insertIndex = 1;
		classInfoData = LLVMConstInsertValue(classInfoData, getTypeInfo(base), &insertIndex, 1);
		LLVMSetInitializer(classInfo, classInfoData);
		
		return structPtr;
	}
	
	LLVMTypeRef visit(EnumType t) {
		auto e = t.denum;
		
		if (auto et = e in typeSymbols) {
			return *et;
		}
		
		return typeSymbols[e] = visit(e.type);
	}
	
	LLVMTypeRef visit(BuiltinType t) {
		final switch(t.kind) with(TypeKind) {
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
	
	LLVMTypeRef visit(PointerType t) {
		auto pointed = visit(t.pointed);
		
		if(LLVMGetTypeKind(pointed) == LLVMTypeKind.Void) {
			pointed = LLVMInt8TypeInContext(llvmCtx);
		}
		
		return LLVMPointerType(pointed, 0);
	}
	
	LLVMTypeRef visit(SliceType t) {
		LLVMTypeRef[2] types;
		types[0] = LLVMInt64TypeInContext(llvmCtx);
		types[1] = LLVMPointerType(visit(t.sliced), 0);
		
		return LLVMStructTypeInContext(llvmCtx, types.ptr, 2, false);
	}
	
	LLVMTypeRef visit(ArrayType t) {
		auto type = visit(t.elementType);
		
		return LLVMArrayType(type, cast(uint) t.size);
	}
	
	private auto buildParamType(ParamType pt) {
		auto type = visit(pt.type);
		
		if(pt.isRef) {
			type = LLVMPointerType(type, 0);
		}
		
		return type;
	}
	
	LLVMTypeRef visit(FunctionType t) {
		auto params = t.paramTypes.map!(p => buildParamType(p)).array();
		
		return LLVMPointerType(LLVMFunctionType(buildParamType(t.returnType), params.ptr, cast(uint) params.length, t.isVariadic), 0);
	}
	
	LLVMTypeRef visit(DelegateType t) {
		LLVMTypeRef[] params;
		params.length = t.paramTypes.length + 1;
		params[0] = buildParamType(t.context);
		
		foreach(i, pt; t.paramTypes) {
			params[i + 1] = buildParamType(pt);
		}
		
		auto fun = LLVMFunctionType(buildParamType(t.returnType), params.ptr, cast(uint) params.length, t.isVariadic);
		
		LLVMTypeRef[2] types;
		types[0] = LLVMPointerType(fun, 0);
		types[1] = params[0];
		
		return LLVMStructTypeInContext(llvmCtx, types.ptr, 2, false);
	}
	
	LLVMTypeRef visit(ContextType t) {
		auto closure = contexts[$ - 1];
		return closure.context
			? LLVMGetElementType(LLVMTypeOf(closure.context))
			: LLVMInt8TypeInContext(llvmCtx);
	}
}

