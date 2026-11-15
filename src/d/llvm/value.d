module d.llvm.value;

import d.llvm.local;

import d.ir.type;

import llvm.c.core;

struct ValueGen {
	private LocalPass pass;
	alias pass this;

	this(LocalPass pass) {
		this.pass = pass;
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
