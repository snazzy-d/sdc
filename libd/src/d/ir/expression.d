module d.ir.expression;

import d.ir.symbol;
import d.ir.type;

import d.ast.expression;

import d.context.location;
import d.context.name;

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

Expression build(E, T...)(T args) if (is(E : Expression) && is(typeof(new E(T.init)))) {
	import d.ir.error;
	if (auto ce = errorize(args)) {
		return ce.expression;
	}
	
	return new E(args);
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
	
	override string toString(const Context c) const {
		return unarizeString(expr.toString(c), op);
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
	
	override string toString(const Context c) const {
		import std.algorithm, std.range;
		auto aa = args.map!(a => a.toString(c)).join(", ");
		return callee.toString(c) ~ "(" ~ aa ~ ")";
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
	
	override string toString(const Context c) const {
		return indexed.toString(c) ~ "[" ~ index.toString(c) ~ "]";
	}
	
	@property
	override bool isLvalue() const {
		// FIXME: make this const compliant
		auto t = (cast() indexed.type).getCanonical();
		return t.kind == TypeKind.Slice|| t.kind == TypeKind.Pointer || indexed.isLvalue;
	}
}

/**
 * Slice expression : [first .. second]
 */
class SliceExpression : Expression {
	Expression sliced;
	
	Expression first;
	Expression second;
	
	this(
		Location location,
		Type type,
		Expression sliced,
		Expression first,
		Expression second,
	) {
		super(location, type);
		
		this.sliced = sliced;
		this.first = first;
		this.second = second;
	}
	
	override string toString(const Context c) const {
		return sliced.toString(c)
			~ "[" ~ first.toString(c) ~ " .. " ~ second.toString(c) ~ "]";
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
 * Super
 */
class SuperExpression : Expression {
	this(Location location) {
		super(location, Type.get(BuiltinType.None));
	}
	
	this(Location location, Type type) {
		super(location, type);
	}
	
	override string toString(const Context) const {
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
	
	override string toString(const Context) const {
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
	
	override string toString(const Context c) const {
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
	
	override string toString(const Context) const {
		return value ? "true" : "false";
	}
}

/**
 * Integer literal
 */
class IntegerLiteral : CompileTimeExpression {
	ulong value;
	
	this(Location location, ulong value, BuiltinType t) in {
		assert(isIntegral(t));
	} body {
		super(location, Type.get(t));
		
		this.value = value;
	}
	
	override string toString(const Context) const {
		import std.conv;
		return isSigned(type.builtin)
			? to!string(cast(long) value)
			: to!string(value);
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
	dchar value;
	
	this(Location location, dchar value, BuiltinType t) in {
		assert(isChar(t));
	} body {
		super(location, Type.get(t));
		
		this.value = value;
	}
	
	override string toString(const Context) const {
		import std.conv;
		return "'" ~ to!string(value) ~ "'";
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
	
	override string toString(const Context) const {
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
	
	override string toString(const Context) const {
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
	
	override string toString(const Context c) const {
		return "cast(" ~ type.toString(c) ~ ") " ~ expr.toString(c);
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
	
	override string toString(const Context c) const {
		import std.algorithm, std.range;
		auto aa = args.map!(a => a.toString(c)).join(", ");
		return "new " ~ type.toString(c) ~ "(" ~ aa ~ ")";
	}
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
	
	override string toString(const Context c) const {
		return var.name.toString(c);
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
	
	override string toString(const Context c) const {
		return expr.toString(c) ~ "." ~ field.name.toString(c);
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
	
	override string toString(const Context c) const {
		return fun.name.toString(c);
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
	
	override string toString(const Context c) const {
		return expr.toString(c) ~ "." ~ method.name.toString(c);
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
	
	override string toString(const Context c) const {
		return "typeid(" ~ argument.toString(c) ~ ")";
	}
}

/**
 * Used for type identifier = void;
 */
class VoidInitializer : CompileTimeExpression {
	this(Location location, Type type) {
		super(location, type);
	}
	
	override string toString(const Context) const {
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
		
		override string toString(const Context c) const {
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
