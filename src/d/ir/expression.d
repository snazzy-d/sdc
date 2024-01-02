module d.ir.expression;

import d.ir.constant;
import d.ir.symbol;
import d.ir.type;

import d.ast.expression;

import d.common.node;

import source.context;
import source.location;
import source.name;

abstract class Expression : AstExpression {
	Type type;

	this(Location location, Type type) {
		super(location);

		this.type = type;
	}

	@property
	bool isLvalue() const {
		return false;
	}

	override string toString(const Context) const {
		import std.format;
		assert(0, format!"toString not implement for %s."(typeid(this)));
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

/**
 * Any expression that have a value known at compile time.
 */
abstract class CompileTimeExpression : Expression {
	this(Location location, Type type) {
		super(location, type);
	}
}

final:
/**
 * This serves as a bridge to d.ir.constant .
 */
class ConstantExpression : CompileTimeExpression {
	Constant value;

	this(Location location, Constant value) {
		super(location, value.type);

		this.value = value;
	}

	override string toString(const Context c) const {
		return value.toString(c);
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
	AddressOf,
	Dereference,
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
		case AddressOf:
			return "&" ~ s;

		case Dereference:
			return "*" ~ s;

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

	@property
	override bool isLvalue() const {
		return op == UnaryOp.Dereference;
	}
}

enum BinaryOp {
	Comma,
	Assign,
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
}

class CallExpression : Expression {
	Expression callee;
	Expression[] arguments;

	this(Location location, Type type, Expression callee,
	     Expression[] arguments) {
		super(location, type);

		this.callee = callee;
		this.arguments = arguments;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"%s(%-(%s, %))"(callee.toString(c),
		                              arguments.map!(a => a.toString(c)));
	}

	@property
	override bool isLvalue() const {
		return callee.type.asFunctionType().returnType.isRef;
	}
}

enum Intrinsic {
	None,
	Expect,
	FetchAdd,
	FetchSub,
	FetchAnd,
	FetchOr,
	FetchXor,
	CompareAndSwap,
	CompareAndSwapWeak,
	PopCount,
	CountLeadingZeros,
	CountTrailingZeros,
	ByteSwap,
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
 * Index expression : indexed[index]
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
		return format!"%s[%s]"(indexed.toString(c), index.toString(c));
	}

	@property
	override bool isLvalue() const {
		// FIXME: make this const compliant
		auto t = (cast() indexed.type).getCanonical();
		if (t.kind == TypeKind.Slice || t.kind == TypeKind.Pointer) {
			return true;
		}

		return indexed.isLvalue;
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
 * Context
 */
class ContextExpression : Expression {
	this(Location location, Function f) {
		super(location, Type.getContextType(f));
	}

	override string toString(const Context) const {
		return "__ctx";
	}

	@property
	override bool isLvalue() const {
		return true;
	}
}

/**
 * String literal
 */
class StringLiteral : CompileTimeExpression {
	string value;

	this(Location location, string value) {
		super(location,
		      Type.get(BuiltinType.Char).getSlice(TypeQualifier.Immutable));

		this.value = value;
	}

	override string toString(const Context) const {
		string[1] x = [value];

		import std.format;
		return format!"%(%s%)"(x);
	}
}

class CStringLiteral : CompileTimeExpression {
	string value;

	this(Location location, string value) {
		super(location,
		      Type.get(BuiltinType.Char).getPointer(TypeQualifier.Immutable));

		this.value = value;
	}

	override string toString(const Context) const {
		string[1] x = [value];

		import std.format;
		return format!"%(%s%)"(x);
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
	IntToPtr,
	PtrToInt,
	Down,
	IntToBool,
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

	@property
	override bool isLvalue() const {
		final switch (kind) with (CastKind) {
			case Invalid:
			case IntToPtr:
			case PtrToInt:
			case Down:
			case IntToBool:
			case Trunc:
			case UPad:
			case SPad:
			case FloatTrunc, FloatExtend:
			case FloatToSigned, FloatToUnsigned:
			case SignedToFloat, UnsignedToFloat:
				return false;

			case Bit:
			case Qual:
			case Exact:
				return expr.isLvalue;
		}
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
 * IdentifierExpression that as been resolved as a Variable.
 */
class VariableExpression : Expression {
	Variable var;

	this(Location location, Variable var) {
		super(location, var.type);

		this.var = var;
	}

	override string toString(const Context c) const {
		return var.name.toString(c);
	}

	@property
	override bool isLvalue() const {
		return var.storage != Storage.Enum;
	}
}

/**
 * Field access.
 */
class FieldExpression : Expression {
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

	@property
	override bool isLvalue() const {
		// FIXME: make this const compliant
		auto t = (cast() expr.type).getCanonical();
		if (t.kind == TypeKind.Class || t.kind == TypeKind.Pointer) {
			return true;
		}

		return expr.isLvalue;
	}
}

/**
 * IdentifierExpression that as been resolved as a Function.
 * XXX: Deserve to be merged with VariableExpression somehow.
 */
class FunctionExpression : Expression {
	Function fun;

	this(Location location, Function fun) {
		super(location, fun.type.getType());

		this.fun = fun;
	}

	override string toString(const Context c) const {
		return fun.name.toString(c);
	}
}

/**
 * Delegate from a function + contextes.
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
 * typeid(type) expression.
 * 
 * TODO: Make this a CompileTimeExpression.
 * FIXME: This should simply resolve to the proper symbol.
 */
class StaticTypeidExpression : Expression {
	Type argument;

	this(Location location, Type type, Type argument) {
		super(location, type);

		this.argument = argument;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"typeid(%s)"(argument.toString(c));
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
 * tuples. Also used for struct initialization.
 */
template TupleExpressionImpl(bool isCompileTime = false) {
	static if (isCompileTime) {
		alias E = CompileTimeExpression;
	} else {
		alias E = Expression;
	}

	class TupleExpressionImpl : E {
		E[] values;

		this(Location location, Type t, E[] values) {
			// Implement type tuples.
			super(location, t);

			this.values = values;
		}

		override string toString(const Context c) const {
			// TODO: make this look nice for structs, classes, arrays...
			import std.format, std.algorithm;
			static if (isCompileTime) {
				return format!"ctTuple!(%-(%s, %))"(
					values.map!(v => v.toString(c)));
			} else {
				return
					format!"tuple(%-(%s, %))"(values.map!(v => v.toString(c)));
			}
		}
	}
}

// XXX: required as long as 0 argument instanciation is not possible.
alias TupleExpression = TupleExpressionImpl!false;
alias CompileTimeTupleExpression = TupleExpressionImpl!true;
