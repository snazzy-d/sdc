module d.llvm.constant;

import d.llvm.codegen;

import d.ir.expression;

import util.visitor;

import llvm.c.core;

struct ConstantGen {
	private CodeGen pass;
	alias pass this;

	this(CodeGen pass) {
		this.pass = pass;
	}

	// XXX: This should be removed at some point, but to ease transition.
	LLVMValueRef visit(Expression e) {
		if (auto ce = cast(CompileTimeExpression) e) {
			return visit(ce);
		}

		assert(
			0,
			"Expected a compile time expression, not " ~ typeid(e).toString()
		);
	}

	LLVMValueRef visit(CompileTimeExpression e) {
		return this.dispatch!(function LLVMValueRef(Expression e) {
			import source.exception;
			throw new CompileException(
				e.location, typeid(e).toString() ~ " is not supported");
		})(e);
	}

	LLVMValueRef visit(BooleanLiteral bl) {
		import d.llvm.type;
		return LLVMConstInt(TypeGen(pass).visit(bl.type), bl.value, false);
	}

	LLVMValueRef visit(IntegerLiteral il) {
		import d.ir.type, d.llvm.type;
		return LLVMConstInt(TypeGen(pass).visit(il.type), il.value,
		                    il.type.builtin.isSigned());
	}

	LLVMValueRef visit(FloatLiteral fl) {
		import d.llvm.type;
		return LLVMConstReal(TypeGen(pass).visit(fl.type), fl.value);
	}

	// XXX: character types in backend ?
	LLVMValueRef visit(CharacterLiteral cl) {
		import d.llvm.type;
		return LLVMConstInt(TypeGen(pass).visit(cl.type), cl.value, false);
	}

	LLVMValueRef visit(NullLiteral nl) {
		return llvmNull;
	}

	LLVMValueRef visit(StringLiteral sl) {
		return buildDString(sl.value);
	}

	LLVMValueRef visit(CStringLiteral csl) {
		return buildCString(csl.value);
	}

	LLVMValueRef visit(VoidInitializer v) {
		import d.llvm.type;
		return LLVMGetUndef(TypeGen(pass).visit(v.type));
	}

	LLVMValueRef visit(CompileTimeTupleExpression e) {
		import std.algorithm, std.array;
		auto elts = e.values.map!(v => visit(v)).array();

		import d.llvm.type;
		auto t = TypeGen(pass).visit(e.type);

		switch (LLVMGetTypeKind(t)) with (LLVMTypeKind) {
			case Struct:
				return
					LLVMConstNamedStruct(t, elts.ptr, cast(uint) elts.length);

			case Array:
				auto et = TypeGen(pass).visit(e.type.element);
				return LLVMConstArray(et, elts.ptr, cast(uint) elts.length);

			default:
				break;
		}

		assert(0, "Invalid type tuple.");
	}
}
