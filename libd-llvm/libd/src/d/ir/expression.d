module d.ir.expression;

import d.ast.base;
import d.ast.expression;

import d.ir.symbol;
import d.ir.type;

abstract class Expression : AstExpression {
	QualType type;
	
	this(Location location, QualType type) {
		super(location);
		
		this.type = type;
	}
	
	@property
	bool isLvalue() const {
		return false;
	}
}

alias ConditionalExpression = d.ast.expression.ConditionalExpression!Expression;
alias BinaryExpression = d.ast.expression.BinaryExpression!Expression;
alias UnaryExpression = d.ast.expression.UnaryExpression!Expression;
alias CallExpression = d.ast.expression.CallExpression!Expression;
alias IndexExpression = d.ast.expression.IndexExpression!Expression;
alias SliceExpression = d.ast.expression.SliceExpression!Expression;
alias AssertExpression = d.ast.expression.AssertExpression!Expression;

alias BinaryOp = d.ast.expression.BinaryOp;
alias UnaryOp = d.ast.expression.UnaryOp;

/**
 * Any expression that have a value known at compile time.
 */
abstract class CompileTimeExpression : Expression {
	this(Location location, QualType type) {
		super(location, type);
	}
}

final:
/**
 * An Error occured but an Expression is expected.
 * Useful for speculative compilation.
 */
class ErrorExpression : CompileTimeExpression {
    string message;

    this(Location location, string message) {
        super(location, getBuiltin(TypeKind.None));

        this.message = message;
    }
}

/**
 * Expression that can in fact be several expressions.
 * A good example is IdentifierExpression that resolve as overloaded functions.
 */
class PolysemousExpression : Expression {
	Expression[] expressions;
	
	this(Location location, Expression[] expressions) {
		super(location, getBuiltin(TypeKind.None));
		
		this.expressions = expressions;
	}
	
	invariant() {
		assert(expressions.length > 1);
	}
}

/**
 * This
 */
class ThisExpression : Expression {
	this(Location location) {
		super(location, getBuiltin(TypeKind.None));
	}
	
	this(Location location, QualType type) {
		super(location, type);
	}
	
	override string toString() const {
		return "this";
	}
	
	@property
	override bool isLvalue() const {
		return !(cast(ClassType) type.type);
	}
}

/**
 * Super
 */
class SuperExpression : Expression {
	this(Location location) {
		super(location, getBuiltin(TypeKind.None));
	}
	
	this(Location location, QualType type) {
		super(location, type);
	}
	
	override string toString() const {
		return "super";
	}
	
	@property
	override bool isLvalue() const {
		return true;
	}
}

/**
 * Boolean literal
 */
class BooleanLiteral : CompileTimeExpression {
	bool value;
	
	this(Location location, bool value) {
		super(location, getBuiltin(TypeKind.Bool));
		
		this.value = value;
	}
	
	override string toString() const {
		return value?"true":"false";
	}
}

/**
 * Integer literal
 */
class IntegerLiteral(bool isSigned) : CompileTimeExpression {
	static if(isSigned) {
		alias long ValueType;
	} else {
		alias ulong ValueType;
	}
	
	ValueType value;
	
	this(Location location, ValueType value, TypeKind kind) in {
		assert(isIntegral(kind));
	} body {
		super(location, getBuiltin(kind));
		
		this.value = value;
	}
	
	override string toString() const {
		import std.conv;
		return to!string(value);
	}
}

/**
 * Float literal
 */
class FloatLiteral : CompileTimeExpression {
	double value;
	
	this(Location location, double value, TypeKind kind) in {
		assert(isFloat(kind));
	} body {
		super(location, getBuiltin(kind));
		
		this.value = value;
	}
}

/**
 * Character literal
 */
class CharacterLiteral : CompileTimeExpression {
	string value;
	
	this(Location location, string value, TypeKind kind) in {
		assert(isChar(kind));
	} body {
		super(location, getBuiltin(kind));
		
		this.value = value;
	}
	
	override string toString() const {
		return "'" ~ value ~ "'";
	}
	
	invariant() {
		assert(value.length > 0);
	}
}

/**
 * String literal
 */
class StringLiteral : CompileTimeExpression {
	string value;
	
	this(Location location, string value) {
		auto c = getBuiltin(TypeKind.Char);
		c.qualifier = TypeQualifier.Immutable;
		
		super(location, QualType(new SliceType(c)));
		
		this.value = value;
	}
	
	override string toString() const {
		return "\"" ~ value ~ "\"";
	}
}

/**
 * Null literal
 */
class NullLiteral : CompileTimeExpression {
	this(Location location) {
		super(location, getBuiltin(TypeKind.Null));
	}
	
	override string toString() const {
		return "null";
	}
}

/**
 * Cast expressions
 */
enum CastKind {
	Invalid,
	IntegralToBool,
	Trunc,
	Pad,
	Bit,
	Qual,
	Exact,
}

class CastExpression : Expression {
	Expression expr;
	
	CastKind kind;
	
	this(Location location, CastKind kind, QualType type, Expression expr) {
		super(location, type);
		
		this.kind = kind;
		this.expr = expr;
	}
	
	@property
	override bool isLvalue() const {
		final switch(kind) with(CastKind) {
			case Invalid :
			case IntegralToBool :
			case Trunc :
			case Pad :
				return false;
			
			case Bit :
			case Qual :
			case Exact :
				return expr.isLvalue;
		}
	}
}

/**
 * new
 */
class NewExpression : Expression {
	Expression[] arguments;
	
	this(Location location, QualType type, Expression[] arguments) {
		super(location, type);
		
		this.arguments = arguments;
	}
	
	override string toString() const {
		import std.algorithm, std.range;
		return "new " ~ type.toString() ~ "(" ~ arguments.map!(a => a.toString()).join(", ") ~ ")";
	}
}

/**
 * Symbol expression.
 * IdentifierExpression that as been resolved.
 */
class SymbolExpression : Expression {
	ValueSymbol symbol;
	
	this(Location location, ValueSymbol symbol) {
		super(location, symbol.type);
		
		this.symbol = symbol;
	}
	
	invariant() {
		assert(symbol);
	}
	
	@property
	override bool isLvalue() const {
		return !(symbol.isEnum);
	}
}

/**
 * Field access.
 */
class FieldExpression : Expression {
	Expression expr;
	Field field;
	
	this(Location location, Expression expr, Field field) {
		super(location, field.type);
		
		this.expr = expr;
		this.field = field;
	}
	
	@property
	override bool isLvalue() const {
		return (cast(ClassType) expr.type.type) || expr.isLvalue;
	}
}

/**
 * Methods resolved on expressions.
 */
class MethodExpression : Expression {
	Expression expr;
	Function method;
	
	this(Location location, Expression expr, Function method) {
		auto t = cast(FunctionType) method.type.type;
		type = QualType(new DelegateType(t.linkage, t.returnType, t.paramTypes[0], t.paramTypes[1 .. $], t.isVariadic));
		super(location, type);
		
		this.expr = expr;
		this.method = method;
	}
}

/**
 * Used for type identifier = void;
 */
class VoidInitializer : Expression {
	this(Location location) {
		super(location, getBuiltin(TypeKind.None));
	}
	
	this(Location location, QualType type) {
		super(location, type);
	}
}

/**
 * tuples. Also used for struct initialization.
 */
template TupleExpressionImpl(bool isCompileTime = false) {
	static if(isCompileTime) {
		alias E = CompileTimeExpression;
	} else {
		alias E = Expression;
	}
	
	class TupleExpressionImpl : E {
		E[] values;
	
		this(Location location, E[] values) {
			// Implement type tuples.
			super(location, QualType(null));
		
			this.values = values;
		}
	}
}

// XXX: required as long as 0 argument instanciation is not possible.
alias TupleExpression = TupleExpressionImpl!false;
alias CompileTimeTupleExpression = TupleExpressionImpl!true;

