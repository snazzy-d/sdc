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
		
		this.expr = expr;
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
		return expr.isLvalue;
	}
}

/**
 * Delegates expressions.
 */
class DelegateExpression : Expression {
	Expression context;
	Expression funptr;
	
	this(Location location, Expression context, Expression funptr) {
		auto type = funptr.type;
		auto funType = cast(FunctionType) type.type;
		assert(funType, "funptr must be a function, " ~ type.toString() ~ " given.");
		
		auto dgType = QualType(new DelegateType(funType), type.qualifier);
		super(location, dgType);
		
		this.context = context;
		this.funptr = funptr;
	}
}

/**
 * Methods resolved on expressions.
 */
class MethodExpression : Expression {
	Expression expr;
	Function method;
	
	this(Location location, Expression expr, Function method) {
		super(location, method.type);
		
		this.expr = expr;
		this.method = method;
	}
}

// XXX: Necessary ?
/**
 * type.sizeof
 */
class SizeofExpression : Expression {
	QualType argument;
	
	this(Location location, QualType argument) {
		super(location, getBuiltin(TypeKind.Ulong));
		
		this.argument = argument;
	}
}

/**
 * Used for type identifier = void;
 */
class VoidInitializer : Expression {
	this(Location location) {
		super(location, getBuiltin(TypeKind.None));
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

