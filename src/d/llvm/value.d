module d.llvm.value;

import d.llvm.local;

import d.ir.type;
import d.ir.value;

import llvm.c.core;

struct ValueGen {
	private LocalPass pass;
	alias pass this;

	this(LocalPass pass) {
		this.pass = pass;
	}

	/**
	 * The value is computed by its constant or its expression, and loaded
	 * from there if that is its address.
	 */
	LLVMValueRef visit(Value value) {
		import d.llvm.constant, d.llvm.expression;
		auto v = value.isConstant()
			? ConstantGen(pass.pass).visit(value.constant)
			: ExpressionGen(pass).visit(value.expression);

		if (!value.hasAddress()) {
			return v;
		}

		auto t = value.type.getCanonical();
		return buildLoad(v, typeGen.visit(t), t.qualifier);
	}

	LLVMValueRef buildLoad(LLVMValueRef ptr, LLVMTypeRef type,
	                       TypeQualifier q) {
		auto l = LLVMBuildLoad2(builder, type, ptr, "");
		final switch (q) with (TypeQualifier) {
			case Mutable, Inout, Const:
				break;

			case Shared, ConstShared:
				auto k = LLVMGetTypeKind(type);
				if (k != LLVMTypeKind.Integer && k != LLVMTypeKind.Function
					    && k != LLVMTypeKind.Pointer) {
					import std.format, std.string;
					throw new Exception(
						format!"Cannot generate atomic load for %s"(
							fromStringz(LLVMPrintTypeToString(type))));
				}

				import llvm.c.target;
				LLVMSetAlignment(l, LLVMABIAlignmentOfType(targetData, type));
				LLVMSetOrdering(l, LLVMAtomicOrdering.SequentiallyConsistent);
				break;

			case Immutable:
				// TODO: !invariant.load
				break;
		}

		return l;
	}

	LLVMValueRef buildStore(LLVMValueRef ptr, LLVMValueRef val,
	                        TypeQualifier q) {
		auto s = LLVMBuildStore(builder, val, ptr);
		final switch (q) with (TypeQualifier) {
			case Mutable, Inout, Const:
				break;

			case Shared, ConstShared:
				auto t = LLVMTypeOf(val);
				auto k = LLVMGetTypeKind(t);
				if (k != LLVMTypeKind.Integer && k != LLVMTypeKind.Function
					    && k != LLVMTypeKind.Pointer) {
					import std.format, std.string;
					throw new Exception(
						format!"Cannot generate atomic store for %s"(
							fromStringz(LLVMPrintTypeToString(t))));
				}

				import llvm.c.target;
				LLVMSetAlignment(s, LLVMABIAlignmentOfType(targetData, t));
				LLVMSetOrdering(s, LLVMAtomicOrdering.SequentiallyConsistent);
				break;

			case Immutable:
				// TODO: !invariant.load
				break;
		}

		return s;
	}
}
