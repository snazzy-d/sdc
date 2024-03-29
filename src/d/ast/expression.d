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
	AstExpression ifTrue;
	AstExpression ifFalse;

	this(Location location, AstExpression condition, AstExpression ifTrue,
	     AstExpression ifFalse) {
		super(location);

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
enum AstUnaryOp {
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

string unarizeString(string s, AstUnaryOp op) {
	final switch (op) with (AstUnaryOp) {
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
	AstUnaryOp op;

	this(Location location, AstUnaryOp op, AstExpression expr) {
		super(location);

		this.expr = expr;
		this.op = op;
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
	AstExpression[] arguments;

	this(Location location, AstType type, AstExpression[] arguments) {
		super(location);

		this.type = type;
		this.arguments = arguments;
	}

	override string toString(const Context c) const {
		import std.format, std.algorithm;
		return format!"new %s(%-(%s, %))"(type.toString(c),
		                                  arguments.map!(a => a.toString(c)));
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
 * Null literal
 */
class NullLiteral : AstExpression {
	this(Location location) {
		super(location);
	}

	override string toString(const Context) const {
		return "null";
	}
}

/**
 * Boolean literal
 */
class BooleanLiteral : AstExpression {
	bool value;

	this(Location location, bool value) {
		super(location);

		this.value = value;
	}

	override string toString(const Context) const {
		return value ? "true" : "false";
	}
}

/**
 * Integer literal
 */
class IntegerLiteral : AstExpression {
	BuiltinType type;
	ulong value;

	this(Location location, ulong value, BuiltinType type)
			in(isIntegral(type)) {
		super(location);

		this.type = type;
		this.value = value;
	}

	override string toString(const Context) const {
		import std.conv;
		return isSigned(type) ? to!string(cast(long) value) : to!string(value);
	}
}

/**
 * Float literal
 */
class FloatLiteral : AstExpression {
	BuiltinType type;
	double value;

	this(Location location, double value, BuiltinType type) in(isFloat(type)) {
		super(location);

		this.type = type;
		this.value = value;
	}

	override string toString(const Context) const {
		import std.conv;
		return to!string(value);
	}
}

/**
 * Character literal
 */
class CharacterLiteral : AstExpression {
	BuiltinType type;
	uint value;

	this(Location location, uint value, BuiltinType type) in(isChar(type)) {
		super(location);

		this.type = type;
		this.value = value;
	}

	this(Location location, char value) {
		this(location, value, BuiltinType.Char);
	}

	this(Location location, dchar value) {
		this(location, value, BuiltinType.Dchar);
	}

	override string toString(const Context) const {
		dchar[1] x = [dchar(value)];

		import std.format;
		return format!"%(%s%)"(x);
	}
}

/**
 * String literal
 */
class StringLiteral : AstExpression {
	string value;

	this(Location location, string value) {
		super(location);

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
