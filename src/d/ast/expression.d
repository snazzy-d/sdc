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
		import std.format;
		assert(0, format!"toString not implement for %s."(typeid(this)));
	}
}

final:
/**
 * Conditional expression of type ?:
 */
class AstTernaryExpression : AstExpression {
	AstExpression condition;
	AstExpression lhs;
	AstExpression rhs;

	this(Location location, AstExpression condition, AstExpression lhs,
	     AstExpression rhs) {
		super(location);

		this.condition = condition;
		this.lhs = lhs;
		this.rhs = rhs;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"%s ? %s : %s"(condition.toString(c), lhs.toString(c),
		                             rhs.toString(c));
	}
}

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

AstBinaryOp getBaseOp(AstBinaryOp op) in(isAssign(op)) {
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
		import std.format;
		return format!"%s %s %s"(lhs.toString(c), op, rhs.toString(c));
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
		import std.format;
		return format!"cast(%s) %s"(type.toString(c), expr.toString(c));
	}
}

/**
 * Function call
 */
class AstCallExpression : AstExpression {
	AstExpression callee;
	AstExpression[] arguments;

	this(Location location, AstExpression callee, AstExpression[] arguments) {
		super(location);

		this.callee = callee;
		this.arguments = arguments;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"%s(%-(%s, %))"(callee.toString(c),
		                              arguments.map!(a => a.toString(c)));
	}
}

/**
 * Indetifier calls.
 */
class IdentifierCallExpression : AstExpression {
	Identifier callee;
	AstExpression[] arguments;

	this(Location location, Identifier callee, AstExpression[] arguments) {
		super(location);

		this.callee = callee;
		this.arguments = arguments;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"%s(%-(%s, %))"(callee.toString(c),
		                              arguments.map!(a => a.toString(c)));
	}
}

/**
 * Contructor for builtin types.
 */
class TypeCallExpression : AstExpression {
	AstType type;
	AstExpression[] arguments;

	this(Location location, AstType type, AstExpression[] arguments) {
		super(location);

		this.type = type;
		this.arguments = arguments;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"%s(%-(%s, %))"(type.toString(c),
		                              arguments.map!(a => a.toString(c)));
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

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"%s[%-(%s, %)]"(indexed.toString(c),
		                              arguments.map!(a => a.toString(c)));
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

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"%s[%-(%s, %) .. %-(%s, %)]"(
			sliced.toString(c), first.map!(a => a.toString(c)),
			second.map!(a => a.toString(c)));
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

	override string toString(const Context c) const {
		import std.format;
		return format!"(%s)"(expr.toString(c));
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
		import std.format, std.algorithm;
		return format!"new %s(%-(%s, %))"(type.toString(c),
		                                  args.map!(a => a.toString(c)));
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
 * Super
 */
class SuperExpression : AstExpression {
	this(Location location) {
		super(location);
	}

	override string toString(const Context) const {
		return "super";
	}
}

/**
 * Array literal
 */
class AstArrayLiteral : AstExpression {
	AstExpression[] values;

	this(Location location, AstExpression[] values) {
		super(location);
		this.values = values;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"[%-(%s, %)]"(values.map!(v => v.toString(c)));
	}
}

/**
 * __FILE__ literal
 */
class __File__Literal : AstExpression {
	this(Location location) {
		super(location);
	}

	override string toString(const Context) const {
		return "__FILE__";
	}
}

/**
 * __LINE__ literal
 */
class __Line__Literal : AstExpression {
	this(Location location) {
		super(location);
	}

	override string toString(const Context) const {
		return "__LINE__";
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

	override string toString(const Context) const {
		return "$";
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

	override string toString(const Context c) const {
		import std.format;
		return format!"typeid(%s)"(argument.toString(c));
	}
}

/**
 * typeid(type) expression.
 */
class AstStaticTypeidExpression : AstExpression {
	AstType argument;

	this(Location location, AstType argument) {
		super(location);

		this.argument = argument;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"typeid(%s)"(argument.toString(c));
	}
}

/**
 * Ambiguous typeid expression.
 */
class IdentifierTypeidExpression : AstExpression {
	Identifier argument;

	this(Location location, Identifier argument) {
		super(location);

		this.argument = argument;
	}

	override string toString(const Context c) const {
		import std.format;
		return format!"typeid(%s)"(argument.toString(c));
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
