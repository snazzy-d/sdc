module d.ir.expression;

import d.ir.constant;
import d.ir.symbol;
import d.ir.type;
import d.ir.value;

import d.common.node;

import source.context;
import source.location;
import source.name;

abstract class Expression : Value {
	Location location;

	this(Location location, Type type) {
		super(type);

		this.location = location;
	}

	@property
	bool isLvalue() const {
		return false;
	}
}

Expression build(E, T...)(T args)
		if (is(E : Expression) && is(typeof(new E(T.init)))) {
	import d.ir.error;
	if (auto ce = errorize(args)) {
		return ce.expression;
	}

	return new E(args);
}

final:
/**
 * This serves as a bridge to d.ir.constant .
 */
class ConstantExpression : Expression {
	Constant value;

	this(Location location, Type type, Constant value) {
		super(location, type);

		this.value = value;
	}

	this(Location location, Constant value) {
		this(location, value.type, value);
	}

	override string toString(const Context c) const {
		return value.toString(c);
	}
}

/**
 * Load from an address: *address.
 *
 * Kept as its own node so the address stays first-class. Taking the
 * address of a load is the address expression itself; do not lower
 * dereference through a unary op and then try to recover a constant.
 */
class LoadExpression : Expression {
	Expression address;

	this(Location location, Type type, Expression address) {
		super(location, type);

		this.address = address;
	}

	@property
	override bool isLvalue() const {
		return true;
	}

	override string toString(const Context c) const {
		return "*" ~ address.toString(c);
	}
}

/**
 * Store through an address: *address = value.
 */
class StoreExpression : Expression {
	Expression value;
	Expression address;

	this(Location location, Expression value, Expression address) {
		super(location, value.type);

		this.address = address;
		this.value = value;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"*%s = %s"(address.toString(c), value.toString(c));
	}
}

/**
 * Conditional expression of type ?:
 */
class TernaryExpression : Expression {
	Expression condition;
	Expression ifTrue;
	Expression ifFalse;

	this(Location location, Type type, Expression condition, Expression ifTrue,
	     Expression ifFalse) {
		super(location, type);

		this.condition = condition;
		this.ifTrue = ifTrue;
		this.ifFalse = ifFalse;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"%s ? %s : %s"(condition.toString(c), ifTrue.toString(c),
		                             ifFalse.toString(c));
	}
}

/**
 * Unary Expression types.
 */
enum UnaryOp {
	PreInc,
	PreDec,
	PostInc,
	PostDec,
	Plus,
	Minus,
	Complement,
	Not,
}

string unarizeString(string s, UnaryOp op) {
	final switch (op) with (UnaryOp) {
		case PreInc:
			return "++" ~ s;

		case PreDec:
			return "--" ~ s;

		case PostInc:
			return s ~ "++";

		case PostDec:
			return s ~ "--";

		case Plus:
			return "+" ~ s;

		case Minus:
			return "-" ~ s;

		case Not:
			return "!" ~ s;

		case Complement:
			return "~" ~ s;
	}
}

class UnaryExpression : Expression {
	Expression expr;
	UnaryOp op;

	this(Location location, Type type, UnaryOp op, Expression expr) {
		super(location, type);

		this.expr = expr;
		this.op = op;
	}

	override string toString(const Context c) const {
		return unarizeString(expr.toString(c), op);
	}
}

enum BinaryOp {
	Comma,
	Add,
	Sub,
	Mul,
	Pow,
	UDiv,
	SDiv,
	URem,
	SRem,
	Or,
	And,
	Xor,
	LeftShift,
	UnsignedRightShift,
	SignedRightShift,
	LogicalOr,
	LogicalAnd,
}

class BinaryExpression : Expression {
	BinaryOp op;

	Expression lhs;
	Expression rhs;

	this(Location location, Type type, BinaryOp op, Expression lhs,
	     Expression rhs) {
		super(location, type);

		this.op = op;
		this.lhs = lhs;
		this.rhs = rhs;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"%s %s %s"(lhs.toString(c), op, rhs.toString(c));
	}
}

enum ICmpOp {
	Equal,
	NotEqual,
	GreaterThan,
	GreaterEqual,
	SmallerThan,
	SmallerEqual,
}

/**
 * Integral comparisons (integers, pointers, ...)
 */
class ICmpExpression : Expression {
	ICmpOp op;

	Expression lhs;
	Expression rhs;

	this(Location location, ICmpOp op, Expression lhs, Expression rhs) {
		super(location, Type.get(BuiltinType.Bool));

		this.op = op;
		this.lhs = lhs;
		this.rhs = rhs;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"%s %s %s"(lhs.toString(c), op, rhs.toString(c));
	}
}

enum FPCmpOp {
	Equal,
	NotEqual,
	GreaterThan,
	GreaterEqual,
	SmallerThan,
	SmallerEqual,

	// Weird float operators
	LessGreater,
	LessEqualGreater,
	UnorderedLess,
	UnorderedLessEqual,
	UnorderedGreater,
	UnorderedGreaterEqual,
	Unordered,
	UnorderedEqual,
}

class FPCmpExpression : Expression {
	FPCmpOp op;

	Expression lhs;
	Expression rhs;

	this(Location location, FPCmpOp op, Expression lhs, Expression rhs) {
		super(location, Type.get(BuiltinType.Bool));

		this.op = op;
		this.lhs = lhs;
		this.rhs = rhs;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"%s %s %s"(lhs.toString(c), op, rhs.toString(c));
	}
}

enum LifetimeOp {
	Copy,
	Consume,
	Destroy,
}

class LifetimeExpression : Expression {
	import std.bitmanip;
	mixin(taggedClassRef!(
		// sdfmt off
		Expression, "value",
		LifetimeOp, "op", 2,
		// sdfmt on
	));

	this(Location location, LifetimeOp op, Expression value) {
		super(location, value.type);

		this.op = op;
		this.value = value;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"%s %s"(op, value.toString(c));
	}
}

class CallExpression : Expression {
	Expression callee;
	Expression[] arguments;

	this(Location location, Expression callee, Expression[] arguments) {
		auto returnType =
			callee.type.getCanonical().asFunctionType().returnType;
		auto type = returnType.getType();
		super(location, returnType.isRef ? type.getPointer() : type);

		this.callee = callee;
		this.arguments = arguments;
	}

	@property
	bool refReturn() {
		return callee.type.getCanonical().asFunctionType().returnType.isRef;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"%s(%-(%s, %))"(callee.toString(c),
		                              arguments.map!(a => a.toString(c)));
	}
}

enum Intrinsic {
	None,
	Expect,
	Likely,
	Unlikely,
	Alloca,
	PopCount,
	CountLeadingZeros,
	CountTrailingZeros,
	ByteSwap,
	FetchAdd,
	FetchSub,
	FetchAnd,
	FetchOr,
	FetchXor,
	CompareAndSwap,
	CompareAndSwapWeak,
	ReadCycleCounter,
	ReadFramePointer,
}

/**
 * This is where the compiler does its magic.
 */
class IntrinsicExpression : Expression {
	Intrinsic intrinsic;
	Expression[] arguments;

	this(Location location, Type type, Intrinsic intrinsic,
	     Expression[] arguments) {
		super(location, type);

		this.intrinsic = intrinsic;
		this.arguments = arguments;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"sdc.intrinsics.%s(%-(%s, %))"(
			intrinsic, arguments.map!(a => a.toString(c)));
	}
}

/**
 * Index expression : &indexed[index]
 *
 * The indexed expression is addressable (pointer, slice, or lvalue array).
 */
class IndexExpression : Expression {
	Expression indexed;
	Expression index;

	this(Location location, Type type, Expression indexed, Expression index) {
		super(location, type);

		this.indexed = indexed;
		this.index = index;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"&%s[%s]"(indexed.toString(c), index.toString(c));
	}
}

/**
 * Extract Index expression : indexed[index]
 *
 * Contrary to IndexExpression, this accepts non addressables.
 */
class ExtractIndexExpression : Expression {
	Expression indexed;
	Expression index;

	this(Location location, Type type, Expression indexed, Expression index) {
		super(location, type);

		this.indexed = indexed;
		this.index = index;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"%s[%s]"(indexed.toString(c), index.toString(c));
	}
}

/**
 * Slice expression : sliced[first .. second]
 */
class SliceExpression : Expression {
	Expression sliced;

	Expression first;
	Expression second;

	this(Location location, Type type, Expression sliced, Expression first,
	     Expression second) {
		super(location, type);

		this.sliced = sliced;
		this.first = first;
		this.second = second;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"%s[%s .. %s]"(sliced.toString(c), first.toString(c),
		                             second.toString(c));
	}
}

/**
 * Expression that can in fact be several expressions.
 * A good example is IdentifierExpression that resolve as overloaded functions.
 */
class PolysemousExpression : Expression {
	Expression[] expressions;

	this(Location location, Expression[] expressions) {
		super(location, Type.get(BuiltinType.None));

		this.expressions = expressions;
	}

	invariant() {
		assert(expressions.length > 1);
	}
}

/**
 * Address of the closure context: __ctx.
 */
class ContextExpression : Expression {
	this(Location location, Function f) {
		super(location, Type.getContextType(f).getPointer());
	}

	@property
	Function context() {
		return type.element.context;
	}

	override string toString(const Context) const {
		return "__ctx";
	}
}

/**
 * Array literal
 */
class ArrayLiteral : Expression {
	Expression[] values;

	this(Location location, Type type, Expression[] values) {
		super(location, type);
		this.values = values;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"[%-(%s, %)]"(values.map!(v => v.toString(c)));
	}
}

/**
 * Cast expressions
 */
enum CastKind {
	Invalid,
	UnsignedToPointer,
	SignedToPointer,
	PointerToInt,
	Down,
	IntToBool,
	PointerToBool,
	Trunc,
	UPad,
	SPad,
	FloatToSigned,
	FloatToUnsigned,
	SignedToFloat,
	UnsignedToFloat,
	FloatTrunc,
	FloatExtend,
	Bit,
	Qual,
	Exact,
}

class CastExpression : Expression {
	Expression expr;

	CastKind kind;

	this(Location location, CastKind kind, Type type, Expression expr) {
		super(location, type);

		this.kind = kind;
		this.expr = expr;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"cast(%s) %s"(type.toString(c), expr.toString(c));
	}
}

/**
 * new
 */
class NewExpression : Expression {
	Expression dinit;
	Function ctor;
	Expression[] arguments;

	this(Location location, Type type, Expression dinit, Function ctor,
	     Expression[] arguments) {
		super(location, type);

		this.dinit = dinit;
		this.ctor = ctor;
		this.arguments = arguments;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"new %s(%-(%s, %))"(type.toString(c),
		                                  arguments.map!(a => a.toString(c)));
	}
}

/**
 * A local. An addressable local is the address. A final is the value.
 */
class VariableExpression : Expression {
	Variable var;

	this(Location location, Variable var) in(var.storage != Storage.Enum) {
		super(location, var.isFinal ? var.type : var.type.getPointer());

		this.var = var;
	}

	override string toString(const Context c) const {
		auto name = var.name.toString(c);
		return var.isFinal ? name : "&" ~ name;
	}
}

/**
 * Address of a global.
 */
class GlobalVariableExpression : Expression {
	GlobalVariable var;

	this(Location location, GlobalVariable var) {
		super(location, var.type.getPointer());

		this.var = var;
	}

	override string toString(const Context c) const {
		return var.name.toString(c);
	}
}

/**
 * Address of a field: &expr.field.
 * The base is addressable (class, pointer, or lvalue aggregate).
 */
class FieldExpression : Expression {
	Expression base;
	Field field;

	this(Location location, Expression base, Field field) {
		super(location, field.type.getPointer(base.type.qualifier));

		this.base = base;
		this.field = field;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"&%s.%s"(base.toString(c), field.name.toString(c));
	}
}

/**
 * Field extracted from an rvalue aggregate. Not an address, not an lvalue.
 */
class ExtractFieldExpression : Expression {
	Expression expr;
	Field field;

	this(Location location, Expression expr, Field field) {
		super(location, field.type.qualify(expr.type.qualifier));

		this.expr = expr;
		this.field = field;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"%s.%s"(expr.toString(c), field.name.toString(c));
	}
}

/**
 * Delegate from a function + contexts.
 */
class DelegateExpression : Expression {
	Expression[] contexts;
	Function method;

	this(Location location, Expression[] contexts, Function method) {
		super(location, method.type.getDelegate(contexts.length).getType());

		this.contexts = contexts;
		this.method = method;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"%s.%s"(contexts[$ - 1].toString(c),
		                      method.name.toString(c));
	}
}

/**
 * For classes, typeid is computed at runtime.
 */
class DynamicTypeidExpression : Expression {
	Expression argument;

	this(Location location, Type type, Expression argument) {
		super(location, type);

		this.argument = argument;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"typeid(%s)"(argument.toString(c));
	}
}

/**
 * tuples. Also used for struct/class initialization.
 */
class TupleExpression : Expression {
	Expression[] values;

	this(Location location, Type t, Expression[] values) {
		// Implement type tuples.
		super(location, t);

		this.values = values;
	}

	override string toString(const Context c) const {
		// TODO: make this look nice for structs, classes, arrays...
		import std.format, std.algorithm;
		return format!"tuple(%-(%s, %))"(values.map!(v => v.toString(c)));
	}
}
