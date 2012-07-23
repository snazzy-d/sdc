module d.ast.expression;

import d.ast.ambiguous;
import d.ast.base;
import d.ast.identifier;
import d.ast.statement;
import d.ast.type;

// TODO: allow type change only for ambiguous types.
class Expression : Statement, Namespace {
	Type type;
	
	this(Location location) {
		this(location, new AutoType(location));
	}
	
	this(Location location, Type type) {
		super(location, StatementType.Expression);
		
		this.type = type;
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
			
			case "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "~=", "<<=", ">>=", ">>>=", "^^=", "<<", ">>", ">>>", "^^" :
				type = lhs.type;
				break;
			
			case "||", "&&", "==", "!=", "is", "!is", "in", "!in", "<", "<=", ">", ">=", "<>", "<>=", "!<", "!<=", "!>", "!>=", "!<>", "!<>=" :
				type = new BuiltinType!bool(location);
				break;
			
			case "&", "|", "^", "+", "-", "*", "/", "%" :
				// TODO: pick the biggest type, and promote to unsigned if both signed and unisgned are used.
				type = new AutoType(location);
				break;
			
			case "~" :
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
enum UnaryPrefix {
	None,
	AddressOf,  // &
	PrefixInc,  // ++
	PrefixDec,  // --
	Dereference,  // *
	UnaryPlus,  // +
	UnaryMinus,  // -
	LogicalNot,  // !
	BitwiseNot,  // ~
	Cast,  // cast (type) unaryExpr
	Delete,
}


class PrefixUnaryExpression : Expression {
	Expression expression;
	UnaryPrefix operation;
	
	this(Location location, UnaryPrefix operation, Expression expression) {
		super(location);
		
		this.expression = expression;
		this.operation = operation;
	}
}

/**
 * Unary &
 */
class AddressOfExpression : PrefixUnaryExpression {
	this(Location location, Expression expression) {
		super(location, UnaryPrefix.AddressOf, expression);
	}
}

/**
 * Prefixed ++ and --
 */
class OpAssignUnaryExpression(UnaryPrefix operation) if(
	operation == UnaryPrefix.PrefixInc
	|| operation == UnaryPrefix.PrefixDec
) : PrefixUnaryExpression {
	this(Location location, Expression expression) {
		super(location, operation, expression);
	}
}

/**
 * Unary *
 */
class DereferenceExpression : PrefixUnaryExpression {
	this(Location location, Expression expression) {
		super(location, UnaryPrefix.Dereference, expression);
	}
}

/**
 * Unary + and -
 */
class OperationUnaryExpression(UnaryPrefix operation) if(
	operation == UnaryPrefix.UnaryPlus
	|| operation == UnaryPrefix.UnaryMinus
) : PrefixUnaryExpression {
	this(Location location, Expression expression) {
		super(location, operation, expression);
	}
}

/**
 * !
 */
class NotExpression : PrefixUnaryExpression {
	this(Location location, Expression expression) {
		super(location, UnaryPrefix.LogicalNot, expression);
	}
}

/**
 * Unary ~
 */
class CompelementExpression : PrefixUnaryExpression {
	this(Location location, Expression expression) {
		super(location, UnaryPrefix.BitwiseNot, expression);
	}
}

/**
 * cast(type)
 */
class CastExpression : PrefixUnaryExpression {
	Type type;
	
	this(Location location, Type type, Expression expression) {
		super(location, UnaryPrefix.Cast, expression);
		
		this.type = type;
	}
}

/**
 * cast from a small type to a bigger one (int to long for instance).
 */
class PadExpression : PrefixUnaryExpression {
	Type type;
	
	this(Location location, Type type, Expression expression) {
		super(location, UnaryPrefix.Cast, expression);
		
		this.type = type;
	}
}

/**
 * cast from a big type to a smaller one (long to int for instance).
 */
class TruncateExpression : PrefixUnaryExpression {
	Type type;
	
	this(Location location, Type type, Expression expression) {
		super(location, UnaryPrefix.Cast, expression);
		
		this.type = type;
	}
}

/**
 * delete
 */
class DeleteExpression : PrefixUnaryExpression {
	this(Location location, Expression expression) {
		super(location, UnaryPrefix.Delete, expression);
	}
}

/**
 * Unary Postfix Expression types.
 */
enum PostfixType {
	Primary,
	Dot,  // . QualifiedName  // XXX: specs say a new expression can go here: DMD disagrees.
	PostfixInc,  // ++
	PostfixDec,  // --
	Parens,  // ( ArgumentList* )
	Index,  // [ ArgumentList ]
	Slice,  // [ (ConditionalExpression .. ConditionalExpression)* ]
}

class PostfixUnaryExpression : Expression {
	Expression expression;
	PostfixType operation;
	
	this(Location location, PostfixType operation, Expression expression) {
		super(location);
		
		this.expression = expression;
		this.operation = operation;
	}
}

/**
 * Postfixed ++ and --
 */
class OpAssignUnaryExpression(PostfixType operation) if(
	operation == PostfixType.PostfixInc
	|| operation == PostfixType.PostfixDec
) : PostfixUnaryExpression {
	this(Location location, Expression expression) {
		super(location, operation, expression);
	}
}

/**
 * Function call
 */
class CallExpression : PostfixUnaryExpression {
	Expression[] parameters;
	
	this(Location location, Expression expression, Expression[] parameters) {
		super(location, PostfixType.Parens, expression);
		
		this.parameters = parameters;
	}
}

/**
 * Index expression : [index]
 */
class IndexExpression : PostfixUnaryExpression {
	Expression[] parameters;
	
	this(Location location, Expression expression, Expression[] parameters) {
		super(location, PostfixType.Index, expression);
		
		this.parameters = parameters;
	}
}

/**
 * Identifier expression
 */
class IdentifierExpression : Expression {
	Identifier identifier;
	
	this(Location location, Identifier identifier) {
		super(location);
		
		this.identifier = identifier;
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
 * Integer literals
 */
class IntegerLiteral(bool isSigned) : Expression {
	static if(isSigned) {
		alias long ValueType;
	} else {
		alias ulong ValueType;
	}
	
	ValueType value;
	
	this(Location location, ValueType value, Type type) {
		super(location, type);
		
		this.value = value;
	}
}

import std.traits;
auto makeIntegerLiteral(T)(Location location, T value) if(isIntegral!T) {
	return new IntegerLiteral!(isSigned!T)(location, value, new BuiltinType!T(location));
}

/**
 * String literals
 */
class StringLiteral : Expression {
	string value;
	
	this(Location location, string value) {
		super(location);
		
		this.value = value;
	}
}

/**
 * Character literals
 */
class CharacterLiteral : Expression {
	string value;
	
	this(Location location, string value) {
		super(location);
		
		this.value = value;
	}
}

/**
 * Array literals
 */
class ArrayLiteral : Expression {
	Expression[] values;
	
	this(Location location, Expression[] values) {
		super(location);
		
		this.values = values;
	}
}

/**
 * Boolean literals
 */
class BooleanLiteral(bool value) : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * Null literals
 */
class NullLiteral : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * __FILE__ literals
 */
class __File__Literal : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * __LINE__ literals
 */
class __Line__Literal : Expression {
	this(Location location) {
		super(location);
	}
}

/**
 * Delegate literals
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
 * assert.
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

