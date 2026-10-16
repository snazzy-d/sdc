module d.ir.value;

import d.ir.constant;
import d.ir.error;
import d.ir.expression;
import d.ir.type;

import source.location;

/**
 * A value, in a single pointer-sized word: a payload that is
 * either an expression or a constant, plus two flag bits
 * stored in the low bits of the payload pointer (class
 * objects are always aligned enough to leave them free).
 *
 * Bit 0: the payload is a constant, not an expression.
 * Bit 1: the payload is the address of the value, not the
 *        value itself, so the value has an address.
 * Bit 2 is unused.
 *
 * The payload is recovered by masking the flags out.
 */
struct Value {
private:
	enum ConstantBit = 1;
	enum AddressBit = 2;
	enum FlagMask = ConstantBit | AddressBit;

	void* payload;

	this(void* value, bool constant, bool hasAddress) {
		auto raw = cast(size_t) value;
		assert((raw & FlagMask) == 0, "Value not properly aligned");
		payload = cast(void*) (raw | (constant ? ConstantBit : 0)
			| (hasAddress ? AddressBit : 0));
	}

	void* pointer() const {
		return cast(void*) (cast(size_t) payload & ~FlagMask);
	}

public:
	static Value withValue(Expression expression) {
		return Value(cast(void*) expression, false, false);
	}

	static Value withValue(Constant constant) {
		return Value(cast(void*) constant, true, false);
	}

	static Value withAddress(Expression expression) {
		return Value(cast(void*) expression, false, true);
	}

	static Value withAddress(Constant constant) {
		return Value(cast(void*) constant, true, true);
	}

	bool isConstant() const {
		return (cast(size_t) payload & ConstantBit) != 0;
	}

	bool hasAddress() const {
		return (cast(size_t) payload & AddressBit) != 0;
	}

	@property
	auto expression() inout in(!isConstant(), "Not an expression.") {
		return cast(inout Expression) pointer;
	}

	@property
	auto constant() inout in(isConstant(), "Not a constant.") {
		return cast(inout Constant) pointer;
	}

	@property
	auto type() inout in(payload !is null) {
		// The type sits at the same offset in Constant and
		// Expression, so both branches below read the same
		// address and the optimizer can collapse them into
		// a single load.
		static assert(
			Constant.type.offsetof == Expression.type.offsetof,
			"Expected the type of Value and Expression to be at the same offset.",
		);

		auto found = isConstant() ? constant.type : expression.type;
		if (!hasAddress()) {
			return found;
		}

		auto canonical = found.getCanonical();

		// The type of an error is the error type itself.
		if (canonical.kind == TypeKind.Error) {
			return found;
		}

		return canonical.element;
	}

	/// The value as an expression. A constant becomes a ConstantExpression.
	/// A value that has an address is loaded. A constant address is both.
	Expression getExpression(Location location) in(payload !is null) {
		auto value = isConstant()
			? build!ConstantExpression(location, constant)
			: expression;
		if (!hasAddress()) {
			return value;
		}

		auto canonical = value.type.getCanonical();
		if (canonical.kind != TypeKind.Pointer) {
			return getError(value, location,
			                "Only pointers can be dereferenced.").expression;
		}

		return build!LoadExpression(location, type, value);
	}

	/// The address of the value. A constant address becomes a
	/// ConstantExpression. A value with no address is an error.
	Expression getAddressOf(Location location) in(payload !is null) {
		if (!hasAddress()) {
			if (isConstant()) {
				return getError(constant, location, "Expected an lvalue.")
					.expression;
			}

			return getError(expression, location, "Expected an lvalue.")
				.expression;
		}

		if (isConstant()) {
			return build!ConstantExpression(location, constant);
		}

		return expression;
	}
}

unittest {
	import d.ir.symbol, source.name;

	static assert(Value.sizeof == size_t.sizeof);

	auto location = Location.init;
	auto intType = Type.get(BuiltinType.Int);
	auto ptrType = intType.getPointer();

	// Expression rvalue: returned as-is. It has no address.
	auto rvalue =
		new ConstantExpression(location,
		                       new IntegerConstant(7, BuiltinType.Int));
	auto fromExpr = Value.withValue(rvalue);
	assert(!fromExpr.isConstant());
	assert(!fromExpr.hasAddress());
	assert(fromExpr.type == rvalue.type);
	assert(fromExpr.getExpression(location) is rvalue);

	auto missing = cast(ErrorExpression) fromExpr.getAddressOf(location);
	assert(missing !is null);
	assert(missing.error.message == "Expected an lvalue.");

	// Constant rvalue: wrapped, and still has no address.
	auto constant = new IntegerConstant(42, BuiltinType.Int);
	auto fromConstant = Value.withValue(constant);
	assert(fromConstant.isConstant());
	assert(!fromConstant.hasAddress());
	assert(fromConstant.type == intType);

	auto wrapped =
		cast(ConstantExpression) fromConstant.getExpression(location);
	assert(wrapped !is null);
	assert(wrapped.value is constant);
	assert(wrapped.type == intType);

	auto constantAddress =
		cast(ErrorExpression) fromConstant.getAddressOf(location);
	assert(constantAddress !is null);
	assert(constantAddress.error.message == "Expected an lvalue.");

	// Expression that has an address: load the pointer element.
	auto variable = new Variable(location, intType, BuiltinName!"", null);
	auto addr = new VariableExpression(location, variable);
	assert(addr.type == ptrType);

	auto fromAddr = Value.withAddress(addr);
	assert(!fromAddr.isConstant());
	assert(fromAddr.hasAddress());
	assert(fromAddr.type == intType);
	assert(fromAddr.getAddressOf(location) is addr);

	auto loaded = cast(LoadExpression) fromAddr.getExpression(location);
	assert(loaded !is null);
	assert(loaded.address is addr);
	assert(loaded.type == intType);

	// Constant address: ConstantExpression, then LoadExpression.
	auto nullPtr = new NullConstant(ptrType);
	auto fromNull = Value.withAddress(nullPtr);
	assert(fromNull.isConstant());
	assert(fromNull.hasAddress());
	assert(fromNull.type == intType);

	auto nullAddr = cast(ConstantExpression) fromNull.getAddressOf(location);
	assert(nullAddr !is null);
	assert(nullAddr.value is nullPtr);

	auto nullLoad = cast(LoadExpression) fromNull.getExpression(location);
	assert(nullLoad !is null);
	assert(nullLoad.type == intType);
	auto nullLoadAddr = cast(ConstantExpression) nullLoad.address;
	assert(nullLoadAddr !is null);
	assert(nullLoadAddr.value is nullPtr);

	// Has an address, but the payload is not a pointer.
	auto notPointer = Value.withAddress(constant);
	auto deref = cast(ErrorExpression) notPointer.getExpression(location);
	assert(deref !is null);
	assert(deref.error.message == "Only pointers can be dereferenced.");
	auto raw = cast(ConstantExpression) notPointer.getAddressOf(location);
	assert(raw !is null);
	assert(raw.value is constant);

	// Existing errors win over a newly generated diagnostic.
	auto boom = new CompileError(location, "boom");
	auto errorValue = Value.withValue(boom.expression);
	assert(errorValue.type.kind == TypeKind.Error);
	auto propagated = cast(ErrorExpression) errorValue.getAddressOf(location);
	assert(propagated !is null);
	assert(propagated.error.message == "boom");

	auto errorExprAddress = Value.withAddress(boom.expression);
	assert(errorExprAddress.type.kind == TypeKind.Error);
	assert(errorExprAddress.type.error.message == "boom");

	auto errorAddress = Value.withAddress(boom.constant);
	assert(errorAddress.type.kind == TypeKind.Error);
	assert(errorAddress.type.error.message == "boom");
	auto propagatedLoad =
		cast(ErrorExpression) errorAddress.getExpression(location);
	assert(propagatedLoad !is null);
	assert(propagatedLoad.error.message == "boom");
	auto propagatedAddr =
		cast(ErrorExpression) errorAddress.getAddressOf(location);
	assert(propagatedAddr !is null);
	assert(propagatedAddr.error.message == "boom");
}
