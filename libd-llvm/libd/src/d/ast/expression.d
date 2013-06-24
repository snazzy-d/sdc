module d.ast.expression;

import d.ast.base;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

abstract class AstExpression : Node {
	this(Location location) {
		super(location);
	}
	
	final override string toString() {
		const e = this;
		return e.toString();
	}
	
	string toString() const {
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
	
	override string toString() const {
		return condition.toString() ~ "? " ~ ifTrue.toString() ~ " : " ~ ifFalse.toString();
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
	
	invariant() {
		assert(lhs);
		assert(rhs);
	}
	
	override string toString() const {
		import std.conv;
		return lhs.toString() ~ " " ~ to!string(op) ~ " " ~ rhs.toString();
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
	
	invariant() {
		assert(expr);
	}
	
	override string toString() const {
		import std.conv;
		return to!string(op) ~ expr.toString();
	}
}

alias AstUnaryExpression = UnaryExpression!AstExpression;

class AstCastExpression : AstExpression {
	QualAstType type;
	AstExpression expr;
	
	this(Location location, QualAstType type, AstExpression expr) {
		super(location);
		
		this.expr = expr;
	}
	
	override string toString() const {
		return "cast(" ~ type.toString() ~ ") " ~ expr.toString();
	}
}

/**
 * Function call
 */
class CallExpression(T) if(is(T: AstExpression)) : T {
	T callee;
	T[] arguments;
	
	this(Location location, T callee, T[] arguments) {
		super(location);
		
		this.callee = callee;
		this.arguments = arguments;
	}
	
	override string toString() const {
		import std.algorithm, std.range;
		return callee.toString() ~ "(" ~ arguments.map!(a => a.toString()).join(", ") ~ ")";
	}
}

alias AstCallExpression = CallExpression!AstExpression;

/**
 * Constructor calls.
 */
class ConstructionExpression : AstExpression {
	QualAstType type;
	AstExpression[] arguments;
	
	this(Location location, QualAstType type, AstExpression[] arguments) {
		super(location);
		
		this.type = type;
		this.arguments = arguments;
	}
	
	override string toString() const {
		import std.algorithm, std.range;
		return type.toString() ~ "(" ~ arguments.map!(a => a.toString()).join(", ") ~ ")";
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
	
	override string toString() const {
		import std.algorithm, std.range;
		return callee.toString() ~ "(" ~ arguments.map!(a => a.toString()).join(", ") ~ ")";
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
		super(location);
		
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
	
	override string toString() const {
		return identifier.toString();
	}
}

/**
 * new
 */
class NewExpression : AstExpression {
	QualAstType type;
	AstExpression[] arguments;
	
	this(Location location, QualAstType type, AstExpression[] arguments) {
		super(location);
		
		this.type = type;
		this.arguments = arguments;
	}
	
	override string toString() const {
		import std.algorithm, std.range;
		return "new " ~ type.toString() ~ "(" ~ arguments.map!(a => a.toString()).join(", ") ~ ")";
	}
}

/**
 * Array literal
 */
class ArrayLiteral(T) if(is(T: AstExpression)) : T {
	T[] values;
	
	this(Location location, T[] values) {
		super(location);
		
		this.values = values;
	}
	
	override string toString() const {
		import std.algorithm, std.range;
		return "[" ~ values.map!(v => v.toString()).join(", ") ~ "]";
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
	private Statement statement;
	
	this(Statement statement) {
		super(statement.location);
		
		this.statement = statement;
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
	
	this(Location location, T condition, T message) {
		super(location);
		
		this.condition = condition;
		this.message = message;
	}
}

alias AstAssertExpression = AssertExpression!AstExpression;

/**
 * typeid expression.
 */
class TypeidExpression : AstExpression {
	AstExpression expression;
	
	this(Location location, AstExpression expression) {
		super(location);
		
		this.expression = expression;
	}
}

/**
 * typeid expression with a type as argument.
 */
class StaticTypeidExpression : AstExpression {
	QualAstType argument;
	
	this(Location location, QualAstType argument) {
		super(location);
		
		this.argument = argument;
	}
}

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

