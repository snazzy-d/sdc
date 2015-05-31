module d.ast.expression;

import d.ast.declaration;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

import d.base.name;
import d.base.node;

abstract class AstExpression : Node {
	this(Location location) {
		super(location);
	}
	
	string toString(const ref NameManager nm) const {
		assert(0, "toString not implement for " ~ typeid(this).toString());
	}
}

final:
/**
 * Conditional expression of type ?:
 */
class TernaryExpression(E) : E  if(is(E: AstExpression)){
	E condition;
	E lhs;
	E rhs;
	
	this(U...)(Location location, U args, E condition, E lhs, E rhs) {
		super(location, args);
		
		this.condition = condition;
		this.lhs = lhs;
		this.rhs = rhs;
	}
	
	override string toString(const ref NameManager nm) const {
		return condition.toString(nm) ~ "? " ~ lhs.toString(nm) ~ " : " ~ rhs.toString(nm);
	}
}

alias AstTernaryExpression = TernaryExpression!AstExpression;

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
	SignedRightShift,
	UnsignedRightShift,
	LeftShift,
	SignedRightShiftAssign,
	UnsignedRightShiftAssign,
	LeftShiftAssign,
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

class BinaryExpression(T) : T  if(is(T: AstExpression)){
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
	
	override string toString(const ref NameManager nm) const {
		import std.conv;
		return lhs.toString(nm) ~ " " ~ to!string(op) ~ " " ~ rhs.toString(nm);
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
	Complement,
	Not,
}

string unarizeString(string s, UnaryOp op) {
	final switch(op) with(UnaryOp) {
		case AddressOf :
			return "&" ~ s;
		
		case Dereference :
			return "*" ~ s;
		
		case PreInc :
			return "++" ~ s;
		
		case PreDec :
			return "--" ~ s;
		
		case PostInc :
			return s ~ "++";
		
		case PostDec :
			return s ~ "--";
		
		case Plus :
			return "+" ~ s;
		
		case Minus :
			return "-" ~ s;
		
		case Not :
			return "!" ~ s;
		
		case Complement :
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
	
	override string toString(const ref NameManager nm) const {
		return unarizeString(expr.toString(nm), op);
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
	
	override string toString(const ref NameManager nm) const {
		return "cast(" ~ type.toString(nm) ~ ") " ~ expr.toString(nm);
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
	
	override string toString(const ref NameManager nm) const {
		import std.algorithm, std.range;
		return callee.toString(nm) ~ "(" ~ args.map!(a => a.toString(nm)).join(", ") ~ ")";
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
	
	override string toString(const ref NameManager nm) const {
		import std.algorithm, std.range;
		return callee.toString(nm) ~ "(" ~ args.map!(a => a.toString(nm)).join(", ") ~ ")";
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
	
	this(Location location, AstExpression sliced, AstExpression[] first, AstExpression[] second) {
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
	
	override string toString(const ref NameManager nm) const {
		return identifier.toString(nm);
	}
}

/**
 * new
 */
class NewExpression : AstExpression {
	AstType type;
	AstExpression[] args;
	
	this(Location location, AstType type, AstExpression[] args) {
		super(location);
		
		this.type = type;
		this.args = args;
	}
	
	override string toString(const ref NameManager nm) const {
		import std.algorithm, std.range;
		return "new " ~ type.toString(nm) ~ "(" ~ args.map!(a => a.toString(nm)).join(", ") ~ ")";
	}
}

alias AstNewExpression = NewExpression;

/**
 * Array literal
 */
class ArrayLiteral(T) : T if(is(T: AstExpression)) {
	T[] values;
	
	this(Location location, T[] values) {
		super(location);
		
		this.values = values;
	}
	
	override string toString(const ref NameManager nm) const {
		import std.algorithm, std.range;
		return "[" ~ values.map!(v => v.toString(nm)).join(", ") ~ "]";
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
	AstType tested;
	
	this(Location location, AstType tested) {
		super(location);
		
		this.tested = tested;
	}
}

/**
 * assert
 */
class AssertExpression(T) : T if(is(T: AstExpression)) {
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
class StaticTypeidExpression(T, E) : E if(is(E: AstExpression)) {
	T argument;
	
	this(U...)(Location location, U args, T argument) {
		super(location, args);
		
		this.argument = argument;
	}
}

alias AstStaticTypeidExpression = StaticTypeidExpression!(AstType, AstExpression);

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
	
	override string toString(const ref NameManager) const {
		return "void";
	}
}

