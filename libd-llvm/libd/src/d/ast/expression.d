module d.ast.expression;

import d.ast.base;
import d.ast.declaration;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

abstract class AstExpression : Node {
	this(Location location) {
		super(location);
	}
	
	string toString(Context) const {
		assert(0, "toString not implement for " ~ typeid(this).toString());
	}
}

final:
/**
 * Conditional expression of type ?:
 */
class ConditionalExpression(T) if(is(T: AstExpression)) : T {
	T condition;
	T ifTrue;
	T ifFalse;
	
	this(U...)(Location location, U args, T condition, T ifTrue, T ifFalse) {
		super(location, args);
		
		this.condition = condition;
		this.ifTrue = ifTrue;
		this.ifFalse = ifFalse;
	}
	
	override string toString(Context ctx) const {
		return condition.toString(ctx) ~ "? " ~ ifTrue.toString(ctx) ~ " : " ~ ifFalse.toString(ctx);
	}
}

alias AstConditionalExpression = ConditionalExpression!AstExpression;

/**
 * Binary Expressions.
 */
enum BinaryOp {
	Comma,
	Assign,
	Add,
	Sub,
	Concat,
	Mul,
	Div,
	Mod,
	Pow,
	AddAssign,
	SubAssign,
	ConcatAssign,
	MulAssign,
	DivAssign,
	ModAssign,
	PowAssign,
	LogicalOr,
	LogicalAnd,
	LogicalOrAssign,
	LogicalAndAssign,
	BitwiseOr,
	BitwiseAnd,
	BitwiseXor,
	BitwiseOrAssign,
	BitwiseAndAssign,
	BitwiseXorAssign,
	Equal,
	NotEqual,
	Identical,
	NotIdentical,
	In,
	NotIn,
	LeftShift,
	SignedRightShift,
	UnsignedRightShift,
	LeftShiftAssign,
	SignedRightShiftAssign,
	UnsignedRightShiftAssign,
	Greater,
	GreaterEqual,
	Less,
	LessEqual,
	
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

class BinaryExpression(T) if(is(T: AstExpression)) : T {
	T lhs;
	T rhs;
	
	BinaryOp op;
	
	this(U...)(Location location, U args, BinaryOp op, T lhs, T rhs) {
		super(location, args);
		
		this.lhs = lhs;
		this.rhs = rhs;
		
		this.op = op;
	}
	/+
	invariant() {
		assert(lhs);
		assert(rhs);
	}
	+/
	override string toString(Context ctx) const {
		import std.conv;
		return lhs.toString(ctx) ~ " " ~ to!string(op) ~ " " ~ rhs.toString(ctx);
	}
}

alias AstBinaryExpression = BinaryExpression!AstExpression;

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
	Not,
	Complement,
}

class UnaryExpression(T) if(is(T: AstExpression)) : T {
	T expr;
	
	UnaryOp op;
	
	this(U...)(Location location, U args, UnaryOp op, T expr) {
		super(location, args);
		
		this.expr = expr;
		
		this.op = op;
	}
	/+
	invariant() {
		assert(expr);
	}
	+/
	override string toString(Context ctx) const {
		import std.conv;
		return to!string(op) ~ expr.toString(ctx);
	}
}

alias AstUnaryExpression = UnaryExpression!AstExpression;

class AstCastExpression : AstExpression {
	QualAstType type;
	AstExpression expr;
	
	this(Location location, QualAstType type, AstExpression expr) {
		super(location);
		
		this.type = type;
		this.expr = expr;
	}
	
	override string toString(Context ctx) const {
		return "cast(" ~ type.toString(ctx) ~ ") " ~ expr.toString(ctx);
	}
}

/**
 * Function call
 */
class CallExpression(T) if(is(T: AstExpression)) : T {
	T callee;
	T[] args;
	
	this(U...)(Location location, U pargs, T callee, T[] args) {
		super(location, pargs);
		
		this.callee = callee;
		this.args = args;
	}
	
	override string toString(Context ctx) const {
		import std.algorithm, std.range;
		return callee.toString(ctx) ~ "(" ~ args.map!(a => a.toString(ctx)).join(", ") ~ ")";
	}
}

alias AstCallExpression = CallExpression!AstExpression;

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
	
	override string toString(Context ctx) const {
		import std.algorithm, std.range;
		return callee.toString(ctx) ~ "(" ~ args.map!(a => a.toString(ctx)).join(", ") ~ ")";
	}
}

/**
 * Index expression : [index]
 */
class IndexExpression(T) if(is(T: AstExpression)) : T {
	T indexed;
	T[] arguments;
	
	this(U...)(Location location, U args, T indexed, T[] arguments) {
		super(location, args);
		
		this.indexed = indexed;
		this.arguments = arguments;
	}
}

alias AstIndexExpression = IndexExpression!AstExpression;

/**
 * Slice expression : [first .. second]
 */
class SliceExpression(T) if(is(T: AstExpression)) : T {
	T sliced;
	
	T[] first;
	T[] second;
	
	this(U...)(Location location, U args, T sliced, T[] first, T[] second) {
		super(location, args);
		
		this.sliced = sliced;
		this.first = first;
		this.second = second;
	}
}

alias AstSliceExpression = SliceExpression!AstExpression;

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
	
	override string toString(Context ctx) const {
		return identifier.toString(ctx);
	}
}

/**
 * new
 */
class NewExpression : AstExpression {
	QualAstType type;
	AstExpression[] args;
	
	this(Location location, QualAstType type, AstExpression[] args) {
		super(location);
		
		this.type = type;
		this.args = args;
	}
	
	override string toString(Context ctx) const {
		import std.algorithm, std.range;
		return "new " ~ type.toString(ctx) ~ "(" ~ args.map!(a => a.toString(ctx)).join(", ") ~ ")";
	}
}

alias AstNewExpression = NewExpression;

/**
 * Array literal
 */
class ArrayLiteral(T) if(is(T: AstExpression)) : T {
	T[] values;
	
	this(Location location, T[] values) {
		super(location);
		
		this.values = values;
	}
	
	override string toString(Context ctx) const {
		import std.algorithm, std.range;
		return "[" ~ values.map!(v => v.toString(ctx)).join(", ") ~ "]";
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
	AstBlockStatement fbody;
	
	this(Location location, ParamDecl[] params, bool isVariadic, AstBlockStatement fbody) {
		super(location);
		
		this.params = params;
		this.isVariadic = isVariadic;
		this.fbody = fbody;
	}
	
	this(AstBlockStatement fbody) {
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
	QualAstType tested;
	
	this(Location location, QualAstType tested) {
		super(location);
		
		this.tested = tested;
	}
}

/**
 * assert
 */
class AssertExpression(T) if(is(T: AstExpression)) : T {
	T condition;
	T message;
	
	this(U...)(Location location, U args, T condition, T message) {
		super(location, args);
		
		this.condition = condition;
		this.message = message;
	}
}

alias AstAssertExpression = AssertExpression!AstExpression;

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
class StaticTypeidExpression(T, E) if(is(E: AstExpression)) : E {
	T argument;
	
	this(U...)(Location location, U args, T argument) {
		super(location, args);
		
		this.argument = argument;
	}
}

alias AstStaticTypeidExpression = StaticTypeidExpression!(QualAstType, AstExpression);

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

