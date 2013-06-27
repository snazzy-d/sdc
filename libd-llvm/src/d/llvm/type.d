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
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMValueRef getNewInit(TypeSymbol s) {
		return newInits[s];
	}
	
	LLVMTypeRef visit(QualType t) {
		return visit(t.type);
	}
	
	LLVMTypeRef visit(Type t) {
		return this.dispatch!(function LLVMTypeRef(Type t) {
			assert(0, t.toString() ~ " is not supported");
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
		
		auto llvmStruct = typeSymbols[s] = LLVMStructCreateNamed(context, cast(char*) s.mangle.toStringz());
		
		LLVMTypeRef[] members;
		
		foreach(member; s.members) {
			if(auto f = cast(Field) member) {
				members ~= pass.visit(f.type);
			}
		}
		
		LLVMStructSetBody(llvmStruct, members.ptr, cast(uint) members.length, false);
		
		return llvmStruct;
	}
	
	LLVMTypeRef visit(ClassType t) {
		auto c = t.dclass;
		
		if (auto ct = c in typeSymbols) {
			return *ct;
		}
		
		auto llvmStruct = LLVMStructCreateNamed(context, cast(char*) c.mangle.toStringz());
		auto structPtr = typeSymbols[c] = LLVMPointerType(llvmStruct, 0);
		
		// TODO: typeid instead of null.
		auto vtbl = [LLVMConstNull(LLVMPointerType(LLVMInt8TypeInContext(context), 0))];
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
		auto vtblStruct = LLVMStructCreateNamed(context, cast(char*) (c.mangle ~ "__vtbl").toStringz());
		LLVMStructSetBody(vtblStruct, vtblTypes.ptr, cast(uint) vtblTypes.length, false);
		
		auto vtblPtr = LLVMAddGlobal(dmodule, vtblStruct, (c.mangle ~ "__vtblZ").toStringz());
		LLVMSetInitializer(vtblPtr, LLVMConstNamedStruct(vtblStruct, vtbl.ptr, cast(uint) vtbl.length));
		LLVMSetGlobalConstant(vtblPtr, true);
		
		// Set vtbl.
		fields[0] = vtblPtr;
		auto initTypes = fields.map!(f => LLVMTypeOf(f)).array();
		LLVMStructSetBody(llvmStruct, initTypes.ptr, cast(uint) initTypes.length, false);
		
		auto initPtr = LLVMAddGlobal(dmodule, llvmStruct, (c.mangle ~ "__initZ").toStringz());
		LLVMSetInitializer(initPtr, LLVMConstNamedStruct(llvmStruct, fields.ptr, cast(uint) fields.length));
		LLVMSetGlobalConstant(initPtr, true);
		
		newInits[c] = initPtr;
		
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
				return LLVMVoidTypeInContext(context);
			
			case Bool :
				return LLVMInt1TypeInContext(context);
			
			case Char :
				return LLVMInt8TypeInContext(context);
			
			case Wchar :
				return LLVMInt16TypeInContext(context);
			
			case Dchar :
				return LLVMInt32TypeInContext(context);
			
			case Ubyte :
				return LLVMInt8TypeInContext(context);
			
			case Ushort :
				return LLVMInt16TypeInContext(context);
			
			case Uint :
				return LLVMInt32TypeInContext(context);
			
			case Ulong :
				return LLVMInt64TypeInContext(context);
			
			case Ucent :
				assert(0, "Not Implemented");
			
			case Byte :
				return LLVMInt8TypeInContext(context);
			
			case Short :
				return LLVMInt16TypeInContext(context);
			
			case Int :
				return LLVMInt32TypeInContext(context);
			
			case Long :
				return LLVMInt64TypeInContext(context);
			
			case Cent :
				assert(0, "Not Implemented");
			
			case Float :
				return LLVMFloatTypeInContext(context);
			
			case Double :
				return LLVMDoubleTypeInContext(context);
			
			case Real :
				return LLVMX86FP80TypeInContext(context);
			
			case Null :
				return LLVMPointerType(LLVMInt8TypeInContext(context), 0);
		}
	}
	/+
	LLVMTypeRef visit(BooleanType t) {
		isSigned = false;
		
		return LLVMInt1TypeInContext(context);
	}
	
	LLVMTypeRef visit(IntegerType t) {
		isSigned = !(t.type % 2);
		
		final switch(t.type) with(Integer) {
				case Byte, Ubyte :
					return LLVMInt8TypeInContext(context);
				
				case Short, Ushort :
					return LLVMInt16TypeInContext(context);
				
				case Int, Uint :
					return LLVMInt32TypeInContext(context);
				
				case Long, Ulong :
					return LLVMInt64TypeInContext(context);
		}
	}
	
	LLVMTypeRef visit(FloatType t) {
		isSigned = true;
		
		final switch(t.type) with(Float) {
				case Float :
					return LLVMFloatTypeInContext(context);
				
				case Double :
					return LLVMDoubleTypeInContext(context);
				
				case Real :
					return LLVMX86FP80TypeInContext(context);
		}
	}
	
	// XXX: character type in the backend ?
	LLVMTypeRef visit(CharacterType t) {
		isSigned = false;
		
		final switch(t.type) with(Character) {
				case Char :
					return LLVMInt8TypeInContext(context);
				
				case Wchar :
					return LLVMInt16TypeInContext(context);
				
				case Dchar :
					return LLVMInt32TypeInContext(context);
		}
	}
	
	LLVMTypeRef visit(VoidType t) {
		return LLVMVoidTypeInContext(context);
	}
	+/
	LLVMTypeRef visit(PointerType t) {
		auto pointed = visit(t.pointed);
		
		if(LLVMGetTypeKind(pointed) == LLVMTypeKind.Void) {
			pointed = LLVMInt8TypeInContext(context);
		}
		
		return LLVMPointerType(pointed, 0);
	}
	
	LLVMTypeRef visit(SliceType t) {
		LLVMTypeRef[2] types;
		types[0] = LLVMInt64TypeInContext(context);
		types[1] = LLVMPointerType(visit(t.sliced), 0);
		
		return LLVMStructTypeInContext(context, types.ptr, 2, false);
	}
	/+
	LLVMTypeRef visit(StaticArrayType t) {
		auto type = visit(t.type);
		auto size = pass.visit(t.size);
		
		return LLVMArrayType(type, cast(uint) LLVMConstIntGetZExtValue(size));
	}
	+/
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
	/+
	LLVMTypeRef visit(DelegateType t) {
		LLVMTypeRef[] params;
		params.length = t.parameters.length + 1;
		params[0] = buildParameterType(t.context);
		
		foreach(i, p; t.parameters) {
			params[i + 1] = buildParameterType(p);
		}
		
		auto fun = LLVMFunctionType(visit(t.returnType), params.ptr, cast(uint) params.length, t.isVariadic);
		
		LLVMTypeRef[2] types;
		types[0] = LLVMPointerType(fun, 0);
		types[1] = params[0];
		
		return LLVMStructTypeInContext(context, types.ptr, 2, false);
	}
	+/
}

