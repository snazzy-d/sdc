module d.llvm.constant;

import d.llvm.codegen;

import d.ir.expression;

import util.visitor;

import llvm.c.core;

struct ConstantGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	// XXX: This should be removed at some point, but to ease transition.
	LLVMValueRef visit(Expression e) {
		if (auto ce = cast(CompileTimeExpression) e) {
			return visit(ce);
		}
		
		assert(0, "Expected a compile time expression, not " ~ typeid(e).toString());
	}
	
	LLVMValueRef visit(CompileTimeExpression e) {
		return this.dispatch!(function LLVMValueRef(Expression e) {
			import d.exception;
			throw new CompileException(e.location, typeid(e).toString() ~ " is not supported");
		})(e);
	}
	
	LLVMValueRef visit(BooleanLiteral bl) {
		return LLVMConstInt(pass.visit(bl.type), bl.value, false);
	}
	
	LLVMValueRef visit(IntegerLiteral il) {
		import d.ir.type;
		return LLVMConstInt(pass.visit(il.type), il.value, isSigned(il.type.builtin));
	}
	
	LLVMValueRef visit(FloatLiteral fl) {
		return LLVMConstReal(pass.visit(fl.type), fl.value);
	}
	
	// XXX: character types in backend ?
	LLVMValueRef visit(CharacterLiteral cl) {
		return LLVMConstInt(pass.visit(cl.type), cl.value, false);
	}
	
	LLVMValueRef visit(NullLiteral nl) {
		return LLVMConstNull(pass.visit(nl.type));
	}
	
	LLVMValueRef visit(StringLiteral sl) {
		return buildDString(sl.value);
	}
	
	LLVMValueRef visit(VoidInitializer v) {
		return LLVMGetUndef(pass.visit(v.type));
	}
	
	LLVMValueRef visit(CompileTimeTupleExpression e) {
		import std.algorithm, std.array;
		auto fields = e.values.map!(v => visit(v)).array();
		auto t = pass.visit(e.type);
		
		switch(LLVMGetTypeKind(t)) with(LLVMTypeKind) {
			case Struct :
				return LLVMConstNamedStruct(t, fields.ptr, cast(uint) fields.length);
			
			case Array :
				return LLVMConstArray(LLVMGetElementType(t), fields.ptr, cast(uint) fields.length);
			
			default :
				break;
		}
		
		assert(0, "Invalid type tuple.");
	}
}
