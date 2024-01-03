module d.llvm.constant;

import d.llvm.codegen;

import d.ir.constant;
import d.ir.expression;

import util.visitor;

import llvm.c.core;

struct ConstantData {
private:
	LLVMValueRef[string] stringLiterals;
}

struct ConstantGen {
	private CodeGen pass;
	alias pass this;

	this(CodeGen pass) {
		this.pass = pass;
	}

	@property
	auto typeGen() {
		import d.llvm.type;
		return TypeGen(pass);
	}

	// XXX: lack of multiple alias this, so we do it automanually.
	private {
		@property
		ref LLVMValueRef[string] stringLiterals() {
			return pass.constantData.stringLiterals;
		}
	}

	LLVMValueRef visit(Constant c) {
		return this.dispatch(c);
	}

	LLVMValueRef visit(VoidConstant c) {
		return LLVMGetUndef(typeGen.visit(c.type));
	}

	LLVMValueRef visit(NullConstant c) {
		return llvmNull;
	}

	LLVMValueRef visit(BooleanConstant b) {
		return LLVMConstInt(i1, b.value, false);
	}

	LLVMValueRef visit(IntegerConstant i) {
		import d.ir.type;
		return LLVMConstInt(typeGen.visit(i.type), i.value,
		                    i.type.builtin.isSigned());
	}

	LLVMValueRef visit(FloatConstant f) {
		return LLVMConstReal(typeGen.visit(f.type), f.value);
	}

	LLVMValueRef visit(CharacterConstant c) {
		return LLVMConstInt(typeGen.visit(c.type), c.value, false);
	}

	LLVMValueRef visit(StringConstant s) {
		return buildDString(s.value);
	}

	LLVMValueRef visit(CStringConstant cs) {
		return buildCString(cs.value);
	}

	private auto buildStringConstant(string str)
			in(str.length <= uint.max, "string length must be < uint.max") {
		return stringLiterals.get(str, stringLiterals[str] = {
			auto charArray =
				LLVMConstStringInContext(llvmCtx, str.ptr,
				                         cast(uint) str.length, true);

			auto type = LLVMTypeOf(charArray);
			auto globalVar = LLVMAddGlobal(dmodule, type, ".str");
			LLVMSetInitializer(globalVar, charArray);
			LLVMSetLinkage(globalVar, LLVMLinkage.Private);
			LLVMSetGlobalConstant(globalVar, true);
			LLVMSetUnnamedAddr(globalVar, true);

			auto zero = LLVMConstInt(i32, 0, true);
			LLVMValueRef[2] indices = [zero, zero];
			return LLVMConstInBoundsGEP2(type, globalVar, indices.ptr,
			                             indices.length);
		}());
	}

	auto buildCString(string str) {
		import std.string;
		auto cstr = str.toStringz()[0 .. str.length + 1];
		return buildStringConstant(cstr);
	}

	auto buildDString(string str) {
		LLVMValueRef[2] slice =
			[LLVMConstInt(i64, str.length, false), buildStringConstant(str)];
		return
			LLVMConstStructInContext(llvmCtx, slice.ptr, slice.length, false);
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

	LLVMValueRef visit(CompileTimeTupleExpression e) {
		import std.algorithm, std.array;
		auto elts = e.values.map!(v => visit(v)).array();

		auto t = typeGen.visit(e.type);
		switch (LLVMGetTypeKind(t)) with (LLVMTypeKind) {
			case Struct:
				return
					LLVMConstNamedStruct(t, elts.ptr, cast(uint) elts.length);

			case Array:
				auto et = typeGen.visit(e.type.element);
				return LLVMConstArray(et, elts.ptr, cast(uint) elts.length);

			default:
				break;
		}

		assert(0, "Invalid type tuple.");
	}
}
