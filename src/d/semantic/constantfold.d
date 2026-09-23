module d.semantic.constantfold;

import d.ir.constant;
import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.common.qualifier;

/**
 * Try to fold an expression into a relocatable / compile-time constant
 * without JIT. Returns null when the expression is not a constant that
 * this folder knows how to represent.
 *
 * This is the path that produces GlobalConstant for `&global`.
 * The LLVM evaluator must not JIT those: a JITed pointer is a host
 * address, not a relocation the linker can resolve.
 */
Constant fold(Expression e) {
	if (e is null) {
		return null;
	}

	if (auto ce = cast(ConstantExpression) e) {
		return ce.value;
	}

	if (auto u = cast(UnaryExpression) e) {
		if (u.op == UnaryOp.AddressOf) {
			return foldAddressOf(u.expr, u.type);
		}

		return null;
	}

	if (auto c = cast(CastExpression) e) {
		return foldCast(c);
	}

	if (auto t = cast(TupleExpression) e) {
		return foldTuple(t);
	}

	if (auto a = cast(ArrayLiteral) e) {
		return foldArray(a);
	}

	return null;
}

/**
 * Fold `&lval` when lval has a link-time address.
 */
Constant foldAddressOf(Expression lval, Type pointerType) {
	if (auto g = cast(GlobalVariableExpression) lval) {
		if (!hasLinkTimeAddress(g.var)) {
			return null;
		}

		return new GlobalConstant(pointerType, g.var);
	}

	// `&func` is already a FunctionConstant (handleAddressOf
	// short-circuits functions). Nothing to do here.

	// Future: `&g.field` and `&g[i]` as GEP constants.
	return null;
}

/**
 * Qualifier / bit / exact casts of constants just retarget the type.
 * Integer conversion of a symbol address is *not* a constant: the
 * numeric value is only known after linking.
 */
Constant foldCast(CastExpression c) {
	auto inner = fold(c.expr);
	if (inner is null) {
		return null;
	}

	final switch (c.kind) with (CastKind) {
		case Exact, Qual, Bit:
			if (auto sa = cast(GlobalConstant) inner) {
				return new GlobalConstant(c.type, sa.symbol);
			}

			if (auto n = cast(NullConstant) inner) {
				return new NullConstant(c.type);
			}

			if (auto f = cast(FunctionConstant) inner) {
				// Function constants already carry their type from
				// the function; a qualifier/bit cast keeps the same
				// LLVM function value.
				return f;
			}

			// Other constants keep their own type representation.
			// If the type changed in a way we don't model, give up.
			if (inner.type == c.type) {
				return inner;
			}

			return null;

		case Invalid, Down:
		case UnsignedToPointer, SignedToPointer, PointerToInt:
		case IntToBool, PointerToBool, Trunc, SPad, UPad:
		case FloatToSigned, FloatToUnsigned:
		case UnsignedToFloat, SignedToFloat:
		case FloatExtend, FloatTrunc:
			return null;
	}
}

Constant foldTuple(TupleExpression t) {
	import std.algorithm, std.array;
	auto elements = t.values.map!(v => fold(v)).array();
	foreach (e; elements) {
		if (e is null) {
			return null;
		}
	}

	auto ct = t.type.getCanonical();
	if (ct.kind == TypeKind.Struct) {
		return new AggregateConstant(ct.dstruct, elements);
	}

	if (ct.kind == TypeKind.Array) {
		return new ArrayConstant(ct.element, elements);
	}

	return new SplatConstant(t.type, elements);
}

Constant foldArray(ArrayLiteral a) {
	import std.algorithm, std.array;
	auto elements = a.values.map!(v => fold(v)).array();
	foreach (e; elements) {
		if (e is null) {
			return null;
		}
	}

	return new ArrayConstant(a.type.element, elements);
}

/**
 * SDC puts mutable / const / inout globals in TLS. Only shared and
 * immutable objects have a single process-wide address the linker
 * can write into an initializer.
 */
bool hasLinkTimeAddress(GlobalVariable g) {
	final switch (g.type.qualifier) with (TypeQualifier) {
		case Mutable, Inout, Const:
			return false;

		case Shared, ConstShared, Immutable:
			return true;
	}
}
