module d.ast.expression;

import d.ast.ambiguous;
import d.ast.base;
import d.ast.declaration;
import d.ast.dscope;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

// TODO: allow type change only for ambiguous types.
class Expression : Node, Namespace {
	Type type;
	
	this(Location location) {
		this(location, new AutoType(location));
	}
	
	this(Location location, Type type) {
		super(location);
		
		this.type = type;
	}
	
	override Symbol resolve(Scope s) {
		assert(0, "resolve not implemented for" ~ typeid(this).toString());
	}
}

/**
 * Conditional expression of type ?:
 */
class ConditionalExpression : Expression {
	Expression condition;
	Expression ifTrue;
	Expression ifFalse;
	
	this(Location location, Expression condition, Expression ifTrue, Expression ifFalse) {
		super(location);
		
		this.condition = condition;
		this.ifTrue = ifTrue;
		this.ifFalse = ifFalse;
	}
}

/**
 * Binary Expressions.
 */
class BinaryExpression(string operator) : Expression {
	Expression lhs;
	Expression rhs;
	
	this(Location location, Expression lhs, Expression rhs) {
		Type type;
		switch(operator) {
			case "," :
				type = rhs.type;
				break;
			
			case "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "~=", "<<=", ">>=", ">>>=", "^^=", "<<", ">>", ">>>", "^^", "~" :
				type = lhs.type;
				break;
			
			case "||", "&&", "==", "!=", "is", "!is", "in", "!in", "<", "<=", ">", ">=", "<>", "<>=", "!<", "!<=", "!>", "!>=", "!<>", "!<>=" :
				type = new BooleanType(location);
				break;
			
			case "&", "|", "^", "+", "-", "*", "/", "%" :
				type = new AutoType(location);
				break;
			
			default:
				assert(0, "Something as gone really wrong and you'll pay for it with blood !");
		}
		
		super(location, type);
		
		this.lhs = lhs;
		this.rhs = rhs;
	}
}

// XXX: Remove ?
alias BinaryExpression!","  CommaExpression;

alias BinaryExpression!"="  AssignExpression;

alias BinaryExpression!"+"  AddExpression;
alias BinaryExpression!"-"  SubExpression;
alias BinaryExpression!"~"  ConcatExpression;
alias BinaryExpression!"*"  MulExpression;
alias BinaryExpression!"/"  DivExpression;
alias BinaryExpression!"%"  ModExpression;
alias BinaryExpression!"^^" PowExpression;

alias BinaryExpression!"+="  AddAssignExpression;
alias BinaryExpression!"-="  SubAssignExpression;
alias BinaryExpression!"~="  ConcatAssignExpression;
alias BinaryExpression!"*="  MulAssignExpression;
alias BinaryExpression!"/="  DivAssignExpression;
alias BinaryExpression!"%="  ModAssignExpression;
alias BinaryExpression!"^^=" PowAssignExpression;

alias BinaryExpression!"||"  LogicalOrExpression;
alias BinaryExpression!"&&"  LogicalAndExpression;

alias BinaryExpression!"||=" LogicalOrAssignExpression;
alias BinaryExpression!"&&=" LogicalAndAssignExpression;

alias BinaryExpression!"|"   BitwiseOrExpression;
alias BinaryExpression!"&"   BitwiseAndExpression;
alias BinaryExpression!"^"   BitwiseXorExpression;

alias BinaryExpression!"|="  BitwiseOrAssignExpression;
alias BinaryExpression!"&="  BitwiseAndAssignExpression;
alias BinaryExpression!"^="  BitwiseXorAssignExpression;

alias BinaryExpression!"=="  EqualityExpression;
alias BinaryExpression!"!="  NotEqualityExpression;

alias BinaryExpression!"is"  IdentityExpression;
alias BinaryExpression!"!is" NotIdentityExpression;

alias BinaryExpression!"in"  InExpression;
alias BinaryExpression!"!in" NotInExpression;

alias BinaryExpression!"<<"  LeftShiftExpression;
alias BinaryExpression!">>"  SignedRightShiftExpression;
alias BinaryExpression!">>>" UnsignedRightShiftExpression;

alias BinaryExpression!"<<="  LeftShiftAssignExpression;
alias BinaryExpression!">>="  SignedRightShiftAssignExpression;
alias BinaryExpression!">>>=" UnsignedRightShiftAssignExpression;

alias BinaryExpression!">"   GreaterExpression;
alias BinaryExpression!">="  GreaterEqualExpression;
alias BinaryExpression!"<"   LessExpression;
alias BinaryExpression!"<="  LessEqualExpression;

alias BinaryExpression!"<>"   LessGreaterExpression;
alias BinaryExpression!"<>="  LessEqualGreaterExpression;
alias BinaryExpression!"!>"   UnorderedLessEqualExpression;
alias BinaryExpression!"!>="  UnorderedLessExpression;
alias BinaryExpression!"!<"   UnorderedGreaterEqualExpression;
alias BinaryExpression!"!<="  UnorderedGreaterExpression;
alias BinaryExpression!"!<>"  UnorderedEqualExpression;
alias BinaryExpression!"!<>=" UnorderedExpression;

/**
 * Unary Prefix Expression types.
 */
class PrefixUnaryExpression(string operation) : Expression {
	Expression expression;
	
	this(Location location, Expression expression) {
		Type type;
		
		switch(operation) {
			case "&", "*", "-" :
				type = new AutoType(location);
				break;
			
			case "++", "--", "+" :
				type = expression.type;
				break;
			
			case "!" :
				type = new BooleanType(location);
				break;
			
			default :
				assert(0, "Something as gone really wrong and you'll pay for it with bloodbloodblood !");
		}
		
		this(location, type, expression);
	}
	
	this(Location location, Type type, Expression expression) {
		super(location, type);
		
		this.expression = expression;
	}
}

alias PrefixUnaryExpression!"&" AddressOfExpression;
alias PrefixUnaryExpression!"*" DereferenceExpression;

alias PrefixUnaryExpression!"++" PreIncrementExpression;
alias PrefixUnaryExpression!"--" PreDecrementExpression;

alias PrefixUnaryExpression!"+" UnaryPlusExpression;
alias PrefixUnaryExpression!"-" UnaryMinusExpression;

alias PrefixUnaryExpression!"!" LogicalNotExpression;
alias PrefixUnaryExpression!"!" NotExpression;

alias PrefixUnaryExpression!"~" BitwiseNotExpression;
alias PrefixUnaryExpression!"~" ComplementExpression;

alias PrefixUnaryExpression!"cast" CastExpression;
alias PrefixUnaryExpression!"pad" PadExpression;
alias PrefixUnaryExpression!"trunc" TruncateExpression;

// FIXME: make this a statement.
alias PrefixUnaryExpression!"delete" DeleteExpression;

/**
 * Unary Postfix Expression types.
 */
class PostfixUnaryExpression(string operation) : Expression {
	Expression expression;
	
	this(Location location, Expression expression) {
		Type type;
		
		switch(operation) {
			case "++", "--" :
				type = expression.type;
				break;
			
			default :
				assert(0, "Something as gone really wrong and you'll pay for it with blood !");
		}
		
		this(location, type, expression);
	}
	
	this(Location location, Type type, Expression expression) {
		super(location, type);
		
		this.expression = expression;
	}
}

alias PostfixUnaryExpression!"++" PostIncrementExpression;
alias PostfixUnaryExpression!"--" PostDecrementExpression;

/**
 * Function call
 */
class CallExpression : Expression {
	Expression callee;
	Expression[] arguments;
	
	this(Location location, Expression callee, Expression[] arguments) {
		super(location);
		
		this.callee = callee;
		this.arguments = arguments;
	}
}

/**
 * Index expression : [index]
 */
class IndexExpression : Expression {
	Expression indexed;
	Expression[] parameters;
	
	this(Location location, Expression indexed, Expression[] parameters) {
		super(location);
		
		this.indexed = indexed;
		this.parameters = parameters;
	}
}

/**
 * Parenthese expression.
 */
class ParenExpression : Expression {
	Expression expression;
	
	this(Location location, Expression expression) {
		super(location, expression.type);
		
		this.expression = expression;
	}
}

/**
 * Identifier expression
 */
class IdentifierExpression : Expression {
	Identifier identifier;
	
	this(Identifier identifier) {
		super(identifier.location);
		
		this.identifier = identifier;
	}
}

/**
 * Symbol expression.
 * IdentifierExpression that as been resolved.
 */
class SymbolExpression : Expression {
	Symbol symbol;
	
	this(Location location, Symbol symbol) {
		super(location);
		
		this.symbol = symbol;
	}
}

/**
 * new
 */
class NewExpression : Expression {
	Type type;
	Expression[] arguments;
	
	this(Location location, Type type, Expression[] arguments) {
		super(location);
		
		this.type = type;
		this.arguments = arguments;
	}
}

/**
 * This
 */
class ThisExpression : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * Super
 */
class SuperExpression : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * Boolean literal
 */
class BooleanLiteral : Expression {
	bool value;
	
	this(Location location, bool value) {
		super(location, new BooleanType(location));
		
		this.value = value;
	}
}

/**
 * Integer literal
 */
class IntegerLiteral(bool isSigned) : Expression {
	static if(isSigned) {
		alias long ValueType;
	} else {
		alias ulong ValueType;
	}
	
	ValueType value;
	
	this(Location location, ValueType value, IntegerType type) {
		super(location, type);
		
		this.value = value;
	}
}

/**
 * Float literal
 */
class FloatLiteral : Expression {
	double value;
	
	this(Location location, real value, FloatType type) {
		super(location, type);
		
		this.value = value;
	}
}

/**
 * Character literal
 */
class CharacterLiteral : Expression {
	string value;
	
	this(Location location, string value, CharacterType type) {
		super(location, type);
		
		this.value = value;
	}
}

/**
 * Factory of literal
 */
auto makeLiteral(T)(Location location, T value) {
	import std.traits;
	static if(is(Unqual!T == bool)) {
		return new BooleanLiteral(location, value);
	} else static if(isIntegral!T) {
		return new IntegerLiteral!(isSigned!T)(location, value, new IntegerType(location, IntegerOf!T));
	} else static if(isFloatingPoint!T) {
		return new FloatLiteral(location, value, new FloatType(location, FloatOf!T));
	} else static if(isSomeChar!T) {
		return new CharacterLiteral(location, [value], new CharacterType(location, CharacterOf!T));
	} else {
		static assert(0, "You can't make litteral for type " ~ T.stringof);
	}
}

/**
 * String literal
 */
class StringLiteral : Expression {
	string value;
	
	this(Location location, string value) {
		super(location);
		
		this.value = value;
	}
}

/**
 * Array literal
 */
class ArrayLiteral : Expression {
	Expression[] values;
	
	this(Location location, Expression[] values) {
		super(location);
		
		this.values = values;
	}
}

/**
 * Null literal
 */
class NullLiteral : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * __FILE__ literal
 */
class __File__Literal : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * __LINE__ literal
 */
class __Line__Literal : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * Delegate literal
 */
class DelegateLiteral : Expression {
	private Statement statement;
	
	this(Statement statement) {
		super(statement.location);
		
		this.statement = statement;
	}
}

/**
 * $
 */
class DollarExpression : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * is expression.
 */
class IsExpression : Expression {
	private Type type;
	
	this(Location location, Type type) {
		super(location);
		
		this.type = type;
	}
}

/**
 * assert
 */
class AssertExpression : Expression {
	private Expression[] arguments;
	
	this(Location location, Expression[] arguments) {
		super(location);
		
		this.arguments = arguments;
	}
}

/**
 * typeid expression.
 */
class TypeidExpression : Expression {
	private Expression expression;
	
	this(Location location, Expression expression) {
		super(location);
		
		this.expression = expression;
	}
}

/**
 * typeid expression with a type as argument.
 */
class StaticTypeidExpression : Expression {
	private Type type;
	
	this(Location location, Type type) {
		super(location);
		
		this.type = type;
	}
}

/**
 * ambiguous typeid expression.
 */
class AmbiguousTypeidExpression : Expression {
	private TypeOrExpression parameter;
	
	this(Location location, TypeOrExpression parameter) {
		super(location);
		
		this.parameter = parameter;
	}
}

