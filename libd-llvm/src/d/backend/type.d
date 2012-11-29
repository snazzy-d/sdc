module d.backend.type;

import d.backend.codegen;

import d.ast.adt;
import d.ast.dfunction;
import d.ast.type;

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
			auto msg = typeid(t).toString() ~ " is not supported.";
			
			import sdc.terminal;
			outputCaretDiagnostics(t.location, msg);
			
			assert(0, msg);
		})(t);
	}
	
	LLVMTypeRef visit(SymbolType t) {
		return pass.visit(t.symbol);
	}
	
	LLVMTypeRef visit(BooleanType t) {
		isSigned = false;
		
		return LLVMInt1Type();
	}
	
	LLVMTypeRef visit(IntegerType t) {
		isSigned = !(t.type % 2);
		
		final switch(t.type) {
				case Integer.Byte, Integer.Ubyte :
					return LLVMInt8Type();
				
				case Integer.Short, Integer.Ushort :
					return LLVMInt16Type();
				
				case Integer.Int, Integer.Uint :
					return LLVMInt32Type();
				
				case Integer.Long, Integer.Ulong :
					return LLVMInt64Type();
		}
	}
	
	LLVMTypeRef visit(FloatType t) {
		isSigned = true;
		
		final switch(t.type) {
				case Float.Float :
					return LLVMFloatType();
				
				case Float.Double :
					return LLVMDoubleType();
				
				case Float.Real :
					return LLVMX86FP80Type();
		}
	}
	
	// XXX: character type in the backend ?
	LLVMTypeRef visit(CharacterType t) {
		isSigned = false;
		
		final switch(t.type) {
				case Character.Char :
					return LLVMInt8Type();
				
				case Character.Wchar :
					return LLVMInt16Type();
				
				case Character.Dchar :
					return LLVMInt32Type();
		}
	}
	
	LLVMTypeRef visit(VoidType t) {
		return LLVMVoidType();
	}
	
	LLVMTypeRef visit(PointerType t) {
		auto pointed = visit(t.type);
		
		return LLVMPointerType(pointed, 0);
	}
	
	LLVMTypeRef visit(SliceType t) {
		auto types = [LLVMInt64Type(), LLVMPointerType(visit(t.type), 0)];
		
		return LLVMStructType(types.ptr, 2, false);
	}
	
	LLVMTypeRef visit(StaticArrayType t) {
		auto type = visit(t.type);
		auto size = pass.visit(t.size);
		
		return LLVMArrayType(type, cast(uint) LLVMConstIntGetZExtValue(size));
	}
	
	LLVMTypeRef visit(EnumType t) {
		return visit(t.type);
	}
	
	LLVMTypeRef visit(FunctionType t) {
		auto parameterTypes = t.parameters.map!((p) {
			auto type = visit(p.type);
			
			if(p.isReference) {
				type = LLVMPointerType(type, 0);
			}
			
			return type;
		}).array();
		
		return LLVMPointerType(LLVMFunctionType(visit(t.returnType), parameterTypes.ptr, cast(uint) parameterTypes.length, t.isVariadic), 0);
	}
}

