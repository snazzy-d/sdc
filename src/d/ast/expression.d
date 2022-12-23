module d.ast.expression;

import d.ast.declaration;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

import d.common.node;

import source.context;
import source.name;

abstract class AstExpression : Node {
	this(Location location) {
		super(location);
	}

	string toString(const Context) const {
		assert(0, "toString not implement for " ~ typeid(this).toString());
	}
}

final:
/**
 * Conditional expression of type ?:
 */
class TernaryExpression(E) : E if (is(E : AstExpression)) {
	E condition;
	E lhs;
	E rhs;

	this(U...)(Location location, U args, E condition, E lhs, E rhs) {
		super(location, args);

		this.condition = condition;
		this.lhs = lhs;
		this.rhs = rhs;
	}

	override string toString(const Context c) const {
		return condition.toString(c) ~ " ? " ~ lhs.toString(c) ~ " : "
			~ rhs.toString(c);
	}
}

alias AstTernaryExpression = TernaryExpression!AstExpression;

/**
 * Binary Expressions.
 */
enum AstBinaryOp {
	Comma,
	Assign,
	Add,
	Sub,
	Mul,
	Pow,
	Div,
	Rem,
	Or,
	And,
	Xor,
	LeftShift,
	UnsignedRightShift,
	SignedRightShift,
	LogicalOr,
	LogicalAnd,
	Concat,
	AddAssign,
	SubAssign,
	MulAssign,
	PowAssign,
	DivAssign,
	RemAssign,
	OrAssign,
	AndAssign,
	XorAssign,
	LeftShiftAssign,
	UnsignedRightShiftAssign,
	SignedRightShiftAssign,
	LogicalOrAssign,
	LogicalAndAssign,
	ConcatAssign,
	Equal,
	NotEqual,
	Identical,
	NotIdentical,
	In,
	NotIn,
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

bool isAssign(AstBinaryOp op) {
	return op >= AstBinaryOp.AddAssign && op <= AstBinaryOp.ConcatAssign;
}

unittest {
	enum Assign = "Assign";
	bool isAssignStupid(AstBinaryOp op) {
		import std.conv;
		auto s = op.to!string();
		if (s.length <= Assign.length) {
			return false;
		}

		return s[$ - Assign.length .. $] == Assign;
	}

	import std.traits;
	foreach (op; EnumMembers!AstBinaryOp) {
		import std.conv;
		assert(op.isAssign() == isAssignStupid(op), op.to!string());
	}
}

AstBinaryOp getBaseOp(AstBinaryOp op) in {
	assert(isAssign(op));
} do {
	return op + AstBinaryOp.Add - AstBinaryOp.AddAssign;
}

unittest {
	enum Assign = "Assign";

	import std.traits;
	foreach (op; EnumMembers!AstBinaryOp) {
		if (!op.isAssign()) {
			continue;
		}

		import std.conv;
		auto b0 = op.to!string()[0 .. $ - Assign.length];
		auto b1 = op.getBaseOp().to!string();
		assert(b0 == b1);
	}
}

class AstBinaryExpression : AstExpression {
	AstBinaryOp op;

	AstExpression lhs;
	AstExpression rhs;

	this(Location location, AstBinaryOp op, AstExpression lhs,
	     AstExpression rhs) {
		super(location);

		this.op = op;
		this.lhs = lhs;
		this.rhs = rhs;
	}

	override string toString(const Context c) const {
		import std.conv;
		return lhs.toString(c) ~ " " ~ to!string(op) ~ " " ~ rhs.toString(c);
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

class AstUnaryExpression : AstExpression {
	AstExpression expr;
	UnaryOp op;

	this(Location location, UnaryOp op, AstExpression expr) {
		super(location);

		this.expr = expr;
		this.op = op;
	}

	invariant() {
		assert(expr);
	}

	override string toString(const Context c) const {
		return unarizeString(expr.toString(c), op);
	}
}

class AstCastExpression : AstExpression {
	AstType type;
	AstExpression expr;

	this(Location location, AstType type, AstExpression expr) {
		super(location);

		this.type = type;
		this.expr = expr;
	}

	override string toString(const Context c) const {
		return "cast(" ~ type.toString(c) ~ ") " ~ expr.toString(c);
	}
}

/**
 * Function call
 */
class AstCallExpression : AstExpression {
	AstExpression callee;
	AstExpression[] args;

	this(Location location, AstExpression callee, AstExpression[] args) {
		super(location);

		this.callee = callee;
		this.args = args;
	}

	override string toString(const Context c) const {
		import std.algorithm, std.range;
		auto aa = args.map!(a => a.toString(c)).join(", ");
		return callee.toString(c) ~ "(" ~ aa ~ ")";
	}
}

/**
 * Indetifier calls.
 */
class IdentifierCallExpression : AstExpression {
	Identifier callee;
	AstExpression[] args;

	this(Location location, Identifier callee, AstExpression[] args) {
		super(location);

		this.callee = callee;
		this.args = args;
	}

	override string toString(const Context c) const {
		import std.algorithm, std.range;
		auto aa = args.map!(a => a.toString(c)).join(", ");
		return callee.toString(c) ~ "(" ~ aa ~ ")";
	}
}

/**
 * Contructor for builtin types.
 */
class TypeCallExpression : AstExpression {
	AstType type;
	AstExpression[] args;

	this(Location location, AstType type, AstExpression[] args) {
		super(location);

		this.type = type;
		this.args = args;
	}

	override string toString(const Context c) const {
		import std.algorithm, std.range;
		auto aa = args.map!(a => a.toString(c)).join(", ");
		return type.toString(c) ~ "(" ~ aa ~ ")";
	}
}

/**
 * Index expression : indexed[arguments]
 */
class AstIndexExpression : AstExpression {
	AstExpression indexed;
	AstExpression[] arguments;

	this(Location location, AstExpression indexed, AstExpression[] arguments) {
		super(location);

		this.indexed = indexed;
		this.arguments = arguments;
	}
}

/**
 * Slice expression : [first .. second]
 */
class AstSliceExpression : AstExpression {
	AstExpression sliced;

	AstExpression[] first;
	AstExpression[] second;

	this(Location location, AstExpression sliced, AstExpression[] first,
	     AstExpression[] second) {
		super(location);

		this.sliced = sliced;
		this.first = first;
		this.second = second;
	}
}

/**
 * Parenthese expression.
 */
class ParenExpression : AstExpression {
	AstExpression expr;

	this(Location location, AstExpression expr) {
		super(location);

		this.expr = expr;
	}
}

/**
 * Identifier expression
 */
class IdentifierExpression : AstExpression {
	Identifier identifier;

	this(Identifier identifier) {
		super(identifier.location);

		this.identifier = identifier;
	}

	override string toString(const Context c) const {
		return identifier.toString(c);
	}
}

/**
 * new
 */
class AstNewExpression : AstExpression {
	AstType type;
	AstExpression[] args;

	this(Location location, AstType type, AstExpression[] args) {
		super(location);

		this.type = type;
		this.args = args;
	}

	override string toString(const Context c) const {
		import std.algorithm, std.range;
		auto aa = args.map!(a => a.toString(c)).join(", ");
		return "new " ~ type.toString(c) ~ "(" ~ aa ~ ")";
	}
}

/**
 * This
 */
class ThisExpression : AstExpression {
	this(Location location) {
		super(location);
	}

	override string toString(const Context) const {
		return "this";
	}
}

/**
 * Array literal
 */
class ArrayLiteral(T) : T if (is(T : AstExpression)) {
	T[] values;

	this(U...)(Location location, U args, T[] values) {
		super(location, args);
		this.values = values;
	}

	override string toString(const Context c) const {
		import std.algorithm, std.range;
		return "[" ~ values.map!(v => v.toString(c)).join(", ") ~ "]";
	}
}

alias AstArrayLiteral = ArrayLiteral!AstExpression;

/**
 * __FILE__ literal
 */
class __File__Literal : AstExpression {
	this(Location location) {
		super(location);
	}
}

/**
 * __LINE__ literal
 */
class __Line__Literal : AstExpression {
	this(Location location) {
		super(location);
	}
}

/**
 * Delegate literal
 */
class DelegateLiteral : AstExpression {
	ParamDecl[] params;
	bool isVariadic;
	BlockStatement fbody;

	this(Location location, ParamDecl[] params, bool isVariadic,
	     BlockStatement fbody) {
		super(location);

		this.params = params;
		this.isVariadic = isVariadic;
		this.fbody = fbody;
	}

	this(BlockStatement fbody) {
		this(fbody.location, [], false, fbody);
	}
}

/**
 * Lambda expressions
 */
class Lambda : AstExpression {
	ParamDecl[] params;
	AstExpression value;

	this(Location location, ParamDecl[] params, AstExpression value) {
		super(location);

		this.params = params;
		this.value = value;
	}
}

/**
 * $
 */
class DollarExpression : AstExpression {
	this(Location location) {
		super(location);
	}
}

/**
 * is expression.
 */
class IsExpression : AstExpression {
	AstType tested;

	this(Location location, AstType tested) {
		super(location);

		this.tested = tested;
	}
}

/**
 * typeid(expression) expression.
 */
class AstTypeidExpression : AstExpression {
	AstExpression argument;

	this(Location location, AstExpression argument) {
		super(location);

		this.argument = argument;
	}
}

/**
 * typeid(type) expression.
 */
class StaticTypeidExpression(T, E) : E if (is(E : AstExpression)) {
	T argument;

	this(U...)(Location location, U args, T argument) {
		super(location, args);

		this.argument = argument;
	}

	override string toString(const Context c) const {
		return "typeid(" ~ argument.toString(c) ~ ")";
	}
}

alias AstStaticTypeidExpression =
	StaticTypeidExpression!(AstType, AstExpression);

/**
 * ambiguous typeid expression.
 */
class IdentifierTypeidExpression : AstExpression {
	Identifier argument;

	this(Location location, Identifier argument) {
		super(location);

		this.argument = argument;
	}
}

/**
 * Used for type identifier = void;
 */
class AstVoidInitializer : AstExpression {
	this(Location location) {
		super(location);
	}

	override string toString(const Context) const {
		return "void";
	}
}
