module d.llvm.type;

import d.llvm.codegen;

import d.ast.adt;
import d.ast.dfunction;
import d.ast.type;

import d.exception;

import util.visitor;

import llvm.c.core;

import std.algorithm;
import std.array;

final class TypeGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMTypeRef visit(Type t) {
		return this.dispatch!(function LLVMTypeRef(Type t) {
			throw new CompileException(t.location, typeid(t).toString() ~ " is not supported");
		})(t);
	}
	
	LLVMTypeRef visit(SymbolType t) {
		return pass.visit(t.symbol);
	}
	
	LLVMTypeRef visit(BooleanType t) {
		isSigned = false;
		
		return LLVMInt1TypeInContext(context);
	}
	
	LLVMTypeRef visit(IntegerType t) {
		isSigned = !(t.type % 2);
		
		final switch(t.type) {
				case Integer.Byte, Integer.Ubyte :
					return LLVMInt8TypeInContext(context);
				
				case Integer.Short, Integer.Ushort :
					return LLVMInt16TypeInContext(context);
				
				case Integer.Int, Integer.Uint :
					return LLVMInt32TypeInContext(context);
				
				case Integer.Long, Integer.Ulong :
					return LLVMInt64TypeInContext(context);
		}
	}
	
	LLVMTypeRef visit(FloatType t) {
		isSigned = true;
		
		final switch(t.type) {
				case Float.Float :
					return LLVMFloatTypeInContext(context);
				
				case Float.Double :
					return LLVMDoubleTypeInContext(context);
				
				case Float.Real :
					return LLVMX86FP80TypeInContext(context);
		}
	}
	
	// XXX: character type in the backend ?
	LLVMTypeRef visit(CharacterType t) {
		isSigned = false;
		
		final switch(t.type) {
				case Character.Char :
					return LLVMInt8TypeInContext(context);
				
				case Character.Wchar :
					return LLVMInt16TypeInContext(context);
				
				case Character.Dchar :
					return LLVMInt32TypeInContext(context);
		}
	}
	
	LLVMTypeRef visit(VoidType t) {
		return LLVMVoidTypeInContext(context);
	}
	
	LLVMTypeRef visit(PointerType t) {
		auto pointed = visit(t.type);
		
		if(LLVMGetTypeKind(pointed) == LLVMTypeKind.Void) {
			pointed = LLVMInt8TypeInContext(context);
		}
		
		return LLVMPointerType(pointed, 0);
	}
	
	LLVMTypeRef visit(SliceType t) {
		auto types = [LLVMInt64TypeInContext(context), LLVMPointerType(visit(t.type), 0)];
		
		return LLVMStructTypeInContext(context, types.ptr, 2, false);
	}
	
	LLVMTypeRef visit(StaticArrayType t) {
		auto type = visit(t.type);
		auto size = pass.visit(t.size);
		
		return LLVMArrayType(type, cast(uint) LLVMConstIntGetZExtValue(size));
	}
	
	LLVMTypeRef visit(EnumType t) {
		return visit(t.type);
	}
	
	private auto buildParameterType(Parameter p) {
		auto type = visit(p.type);
		
		if(p.isReference) {
			type = LLVMPointerType(type, 0);
		}
		
		return type;
	}
	
	LLVMTypeRef visit(FunctionType t) {
		auto params = t.parameters.map!(p => buildParameterType(p)).array();
		
		return LLVMPointerType(LLVMFunctionType(visit(t.returnType), params.ptr, cast(uint) params.length, t.isVariadic), 0);
	}
	
	LLVMTypeRef visit(DelegateType t) {
		LLVMTypeRef[] params;
		params.length = t.parameters.length + 1;
		params[0] = buildParameterType(t.context);
		
		foreach(i, p; t.parameters) {
			params[i + 1] = buildParameterType(p);
		}
		
		auto fun = LLVMFunctionType(visit(t.returnType), params.ptr, cast(uint) params.length, t.isVariadic);
		auto types = [LLVMPointerType(fun, 0), params[0]];
		
		return LLVMStructTypeInContext(context, types.ptr, 2, false);
	}
}

