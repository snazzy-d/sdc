module d.ir.expression;

import d.ir.symbol;
import d.ir.type;

import d.ast.expression;

import d.context;
import d.location;

abstract class Expression : AstExpression {
	Type type;
	
	this(Location location, Type type) {
		super(location);
		
		this.type = type;
	}
	
	@property
	bool isLvalue() const {
		return false;
	}
}

alias TernaryExpression = d.ast.expression.TernaryExpression!Expression;
alias BinaryExpression = d.ast.expression.BinaryExpression!Expression;
alias AssertExpression = d.ast.expression.AssertExpression!Expression;
alias StaticTypeidExpression = d.ast.expression.StaticTypeidExpression!(Type, Expression);

alias BinaryOp = d.ast.expression.BinaryOp;
alias UnaryOp = d.ast.expression.UnaryOp;

/**
 * Any expression that have a value known at compile time.
 */
abstract class CompileTimeExpression : Expression {
	this(Location location, Type type) {
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
		super(location, Type.get(BuiltinType.None));
		
		this.message = message;
	}
	
	override string toString(Context) const {
		return "__error__(" ~ message ~ ")";
	}
}

class UnaryExpression : Expression {
	Expression expr;
	UnaryOp op;
	
	this(Location location, Type type, UnaryOp op, Expression expr) {
		super(location, type);
		
		this.expr = expr;
		this.op = op;
	}
	
	invariant() {
		assert(expr);
	}
	
	override string toString(Context ctx) const {
		return unarizeString(expr.toString(ctx), op);
	}
	
	@property
	override bool isLvalue() const {
		return op == UnaryOp.Dereference;
	}
}

class CallExpression : Expression {
	Expression callee;
	Expression[] args;
	
	this(Location location, Type type, Expression callee, Expression[] args) {
		super(location, type);
		
		this.callee = callee;
		this.args = args;
	}
	
	override string toString(Context ctx) const {
		import std.algorithm, std.range;
		return callee.toString(ctx) ~ "(" ~ args.map!(a => a.toString(ctx)).join(", ") ~ ")";
	}
	
	@property
	override bool isLvalue() const {
		return callee.type.asFunctionType().returnType.isRef;
	}
}

/**
 * Index expression : indexed[arguments]
 */
class IndexExpression : Expression {
	Expression indexed;
	Expression index;
	
	this(Location location, Type type, Expression indexed, Expression index) {
		super(location, type);
		
		this.indexed = indexed;
		this.index = index;
	}
	
	override string toString(Context ctx) const {
		return indexed.toString(ctx) ~ "[" ~ index.toString(ctx) ~ "]";
	}
	
	@property
	override bool isLvalue() const {
		// FIXME: make this const compliant
		auto t = (cast() indexed.type).getCanonical();
		return t.kind == TypeKind.Slice || t.kind == TypeKind.Pointer || indexed.isLvalue;
	}
}

/**
 * Slice expression : [first .. second]
 */
class SliceExpression : Expression {
	Expression sliced;
	
	Expression first;
	Expression second;
	
	this(Location location, Type type, Expression sliced, Expression first, Expression second) {
		super(location, type);
		
		this.sliced = sliced;
		this.first = first;
		this.second = second;
	}
}

/**
 * Expression that can in fact be several expressions.
 * A good example is IdentifierExpression that resolve as overloaded functions.
 */
class PolysemousExpression : Expression {
	Expression[] expressions;
	
	this(Location location, Expression[] expressions) {
		super(location, Type.get(BuiltinType.None));
		
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
		super(location, Type.get(BuiltinType.None));
	}
	
	this(Location location, Type type) {
		super(location, type);
	}
	
	override string toString(Context) const {
		return "this";
	}
	
	@property
	override bool isLvalue() const {
		return type.kind != TypeKind.Class;
	}
}

/**
 * Super
 */
class SuperExpression : Expression {
	this(Location location) {
		super(location, Type.get(BuiltinType.None));
	}
	
	this(Location location, Type type) {
		super(location, type);
	}
	
	override string toString(Context) const {
		return "super";
	}
	
	@property
	override bool isLvalue() const {
		return true;
	}
}

/**
 * Context
 */
class ContextExpression : Expression {
	this(Location location, Function f) {
		super(location, Type.getContextType(f));
	}
	
	override string toString(Context) const {
		return "__ctx";
	}
	
	@property
	override bool isLvalue() const {
		return true;
	}
}

/**
 * Virtual table
 * XXX: This is highly dubious. Explore the alternatives and get rid of that.
 */
class VtblExpression : Expression {
	Class dclass;
	
	this(Location location, Class dclass) {
		super(location, Type.get(BuiltinType.Void).getPointer());
		
		this.dclass = dclass;
	}
	
	override string toString(Context c) const {
		return dclass.toString(c) ~ ".__vtbl";
	}
}

/**
 * Boolean literal
 */
class BooleanLiteral : CompileTimeExpression {
	bool value;
	
	this(Location location, bool value) {
		super(location, Type.get(BuiltinType.Bool));
		
		this.value = value;
	}
	
	override string toString(Context) const {
		return value?"true":"false";
	}
}

/**
 * Integer literal
 */
class IntegerLiteral(bool isSigned) : CompileTimeExpression {
	static if(isSigned) {
		alias ValueType = long;
	} else {
		alias ValueType = ulong;
	}
	
	ValueType value;
	
	this(Location location, ValueType value, BuiltinType t) in {
		assert(isIntegral(t) && .isSigned(t) == isSigned);
	} body {
		super(location, Type.get(t));
		
		this.value = value;
	}
	
	override string toString(Context) const {
		import std.conv;
		return to!string(value);
	}
}

/**
 * Float literal
 */
class FloatLiteral : CompileTimeExpression {
	double value;
	
	this(Location location, double value, BuiltinType t) in {
		assert(isFloat(t));
	} body {
		super(location, Type.get(t));
		
		this.value = value;
	}
}

/**
 * Character literal
 */
class CharacterLiteral : CompileTimeExpression {
	string value;
	
	this(Location location, string value, BuiltinType t) in {
		assert(isChar(t));
	} body {
		super(location, Type.get(t));
		
		this.value = value;
	}
	
	override string toString(Context) const {
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
		super(
			location,
			Type.get(BuiltinType.Char).getSlice(TypeQualifier.Immutable),
		);
		
		this.value = value;
	}
	
	override string toString(Context) const {
		return "\"" ~ value ~ "\"";
	}
}

/**
 * Null literal
 */
class NullLiteral : CompileTimeExpression {
	this(Location location) {
		this(location, Type.get(BuiltinType.Null));
	}
	
	this(Location location, Type t) {
		super(location, t);
	}
	
	override string toString(Context) const {
		return "null";
	}
}

/**
 * Cast expressions
 */
enum CastKind {
	Invalid,
	IntToPtr,
	PtrToInt,
	Down,
	IntToBool,
	Trunc,
	SPad,
	UPad,
	Bit,
	Qual,
	Exact,
}

class CastExpression : Expression {
	Expression expr;
	
	CastKind kind;
	
	this(Location location, CastKind kind, Type type, Expression expr) {
		super(location, type);
		
		this.kind = kind;
		this.expr = expr;
	}
	
	override string toString(Context ctx) const {
		return "cast(" ~ type.toString(ctx) ~ ") " ~ expr.toString(ctx);
	}
	
	@property
	override bool isLvalue() const {
		final switch(kind) with(CastKind) {
			case Invalid :
			case IntToPtr :
			case PtrToInt :
			case Down :
			case IntToBool :
			case Trunc :
			case SPad :
			case UPad :
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
	Expression dinit;
	Expression ctor;
	Expression[] args;
	
	this(Location location, Type type, Expression dinit, Expression ctor, Expression[] args) {
		super(location, type);
		
		this.dinit = dinit;
		this.ctor = ctor;
		this.args = args;
	}
	/+
	override string toString(Context ctx) const {
		import std.algorithm, std.range;
		return "new " ~ type.toString(ctx) ~ "(" ~ args.map!(a => a.toString(ctx)).join(", ") ~ ")";
	}
	+/
}

/**
 * IdentifierExpression that as been resolved as a Variable.
 */
class VariableExpression : Expression {
	Variable var;
	
	this(Location location, Variable var) {
		super(location, var.type);
		
		this.var = var;
	}
	
	override string toString(Context ctx) const {
		return var.name.toString(ctx);
	}
	
	@property
	override bool isLvalue() const {
		return var.storage != Storage.Enum;
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
	
	override string toString(Context ctx) const {
		return expr.toString(ctx) ~ "." ~ field.name.toString(ctx);
	}
	
	@property
	override bool isLvalue() const {
		// FIXME: make this const compliant
		auto t = (cast() expr.type).getCanonical();
		return t.kind == TypeKind.Class || t.kind == TypeKind.Pointer || expr.isLvalue;
	}
}

/**
 * IdentifierExpression that as been resolved as a Function.
 * XXX: Deserve to be merged with VariableExpression somehow.
 */
class FunctionExpression : Expression {
	Function fun;
	
	this(Location location, Function fun) {
		super(location, fun.type.getType());
		
		this.fun = fun;
	}
	
	override string toString(Context ctx) const {
		return fun.name.toString(ctx);
	}
}

/**
 * Methods resolved on expressions.
 */
class MethodExpression : Expression {
	Expression expr;
	Function method;
	
	this(Location location, Expression expr, Function method) {
		super(location, method.type.getDelegate().getType());
		
		this.expr = expr;
		this.method = method;
	}
	
	override string toString(Context ctx) const {
		return expr.toString(ctx) ~ "." ~ method.name.toString(ctx);
	}
}

/**
 * For classes, typeid is computed at runtime.
 */
class DynamicTypeidExpression : Expression {
	Expression argument;
	
	this(Location location, Type type, Expression argument) {
		super(location, type);
		
		this.argument = argument;
	}
	
	override string toString(Context ctx) const {
		return "typeid(" ~ argument.toString(ctx) ~ ")";
	}
}

/**
 * Used for type identifier = void;
 */
class VoidInitializer : CompileTimeExpression {
	this(Location location, Type type) {
		super(location, type);
	}
	
	override string toString(Context) const {
		return "void";
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
		
		this(Location location, Type t, E[] values) {
			// Implement type tuples.
			super(location, t);
			
			this.values = values;
		}
		
		override string toString(Context c) const {
			import std.algorithm, std.range;
			auto members = values.map!(v => v.toString(c)).join(", ");
			
			// TODO: make this look nice for structs, classes, arrays...
			static if (isCompileTime) {
				return "ctTuple!(" ~ members ~ ")";
			} else {
				return "tuple(" ~ members ~ ")";
			}
		}
	}
}

// XXX: required as long as 0 argument instanciation is not possible.
alias TupleExpression = TupleExpressionImpl!false;
alias CompileTimeTupleExpression = TupleExpressionImpl!true;

