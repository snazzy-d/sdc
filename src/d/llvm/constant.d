module d.llvm.constant;

import d.llvm.codegen;

import d.ir.constant;
import d.ir.expression;

import util.visitor;

import llvm.c.core;

struct ConstantGen {
	private CodeGen pass;
	alias pass this;

	this(CodeGen pass) {
		this.pass = pass;
	}

	LLVMValueRef visit(Constant c) {
		return this.dispatch(c);
	}

	LLVMValueRef visit(VoidConstant c) {
		import d.llvm.type;
		return LLVMGetUndef(TypeGen(pass).visit(c.type));
	}

	LLVMValueRef visit(NullConstant c) {
		return llvmNull;
	}

	LLVMValueRef visit(BooleanConstant b) {
		import d.llvm.type;
		return LLVMConstInt(i1, b.value, false);
	}

	// XXX: This should be removed at some point, but to ease transition.
	LLVMValueRef visit(Expression e) {
		if (auto ce = cast(CompileTimeExpression) e) {
			return visit(ce);
		}

		import std.format;
		assert(0,
		       format!"Expected a compile time expression, not %s."(typeid(e)));
	}

	LLVMValueRef visit(CompileTimeExpression e) {
		return this.dispatch!(function LLVMValueRef(Expression e) {
			import source.exception, std.format;
			throw new CompileException(
				e.location, format!"%s is not supported."(typeid(e)));
		})(e);
	}

	LLVMValueRef visit(ConstantExpression e) {
		return visit(e.value);
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

	LLVMValueRef visit(StringLiteral sl) {
		return buildDString(sl.value);
	}

	LLVMValueRef visit(CStringLiteral csl) {
		return buildCString(csl.value);
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
