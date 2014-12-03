module d.ast.type;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.qualtype;

public import d.builtintype;

abstract class AstType {
	final string toString(Context ctx) {
		return toString(ctx, TypeQualifier.Mutable);
	}
	
	string toString(Context, TypeQualifier) const {
		return typeid(this).toString();
	}
}

alias QualAstType = QualType!AstType;
alias ParamAstType = ParamType!AstType;

class BuiltinAstType : AstType {
	BuiltinType kind;
	
	this(BuiltinType kind) {
		this.kind = kind;
	}
}

/**
 * Function types
 */
class FunctionType(T) : T  if(is(T : AstType)){
	ParamType!T returnType;
	ParamType!T[] paramTypes;
	
	import std.bitmanip;
	mixin(bitfields!(
		Linkage, "linkage", 3,
		bool, "isVariadic", 1,
		uint, "", 4,
	));
	
	this(Linkage linkage, ParamType!T returnType, ParamType!T[] paramTypes, bool isVariadic) {
		this.returnType = returnType;
		this.paramTypes = paramTypes;
		this.linkage = linkage;
		this.isVariadic = isVariadic;
	}
	
	override string toString(Context ctx, TypeQualifier qual) const {
		import std.algorithm, std.range;
		return returnType.toString(ctx, qual) ~ " function(" ~ paramTypes.map!(t => t.toString(ctx, qual)).join(", ") ~ (isVariadic?", ...)":")");
	}
}

alias AstFunctionType = FunctionType!AstType;
alias QualAstFunctionType = QualType!AstFunctionType;

final:
/**
 * Type inference
 */
class AutoType : AstType {}

/**
 * Type defined by an identifier
 */
class IdentifierType : AstType {
	Identifier identifier;
	
	this(Identifier identifier) {
		this.identifier = identifier;
	}
	
	override string toString(Context ctx, TypeQualifier) const {
		return identifier.toString(ctx);
	}
}

/**
 * Pointer type
 */
class PointerType(T) : T  if(is(T : AstType)){
	QualType!T pointed;
	
	this(QualType!T pointed) {
		this.pointed = pointed;
	}
	
	override string toString(Context ctx, TypeQualifier qual) const {
		return pointed.toString(ctx, qual) ~ "*";
	}
	
	invariant() {
		assert(pointed.type);
	}
}

alias AstPointerType = PointerType!AstType;

/**
 * Slice type
 */
class SliceType(T) : T  if(is(T : AstType)){
	QualType!T sliced;
	
	this(QualType!T sliced) {
		this.sliced = sliced;
	}
	
	override string toString(Context ctx, TypeQualifier qual) const {
		return sliced.toString(ctx, qual) ~ "[]";
	}
	
	invariant() {
		assert(sliced.type);
	}
}

alias AstSliceType = SliceType!AstType;

/**
 * Associative array type
 */
class AssociativeArrayType(T) : T  if(is(T : AstType)){
	QualType!T keyType;
	QualType!T elementType;
	
	this(QualType!T keyType, QualType!T elementType) {
		this.keyType = keyType;
		this.elementType = elementType;
	}
	
	override string toString(Context ctx, TypeQualifier qual) const {
		return elementType.toString(ctx, qual) ~ "[" ~ keyType.toString(ctx, qual) ~ "]";
	}
}

alias AstAssociativeArrayType = AssociativeArrayType!AstType;

/**
 * Static array types
 */
class AstArrayType : AstType {
	QualAstType elementType;
	AstExpression size;
	
	this(QualAstType elementType, AstExpression size) {
		this.elementType = elementType;
		this.size = size;
	}
	
	override string toString(Context ctx, TypeQualifier qual) const {
		return elementType.toString(ctx, qual) ~ "[" ~ size.toString(ctx) ~ "]";
	}
}

/**
 * Associative or static array types
 */
class IdentifierArrayType : AstType {
	QualAstType elementType;
	Identifier identifier;
	
	this(QualAstType type, Identifier identifier) {
		this.elementType = elementType;
		this.identifier = identifier;
	}
	
	override string toString(Context ctx, TypeQualifier qual) const {
		return elementType.toString(ctx, qual) ~ "[" ~ identifier.toString(ctx) ~ "]";
	}
}

/**
 * Delegate types
 */
class DelegateType(T) : FunctionType!T  if(is(T : AstType)){
	ParamType!T context;
	
	this(Linkage linkage, ParamType!T returnType, ParamType!T context, ParamType!T[] paramTypes, bool isVariadic) {
		super(linkage, returnType, paramTypes, isVariadic);
		
		this.context = context;
	}
	
	this(FunctionType!T t) {
		super(t.linkage, t.returnType, t.paramTypes[1 .. $], t.isVariadic);
		
		context = t.paramTypes[0];
	}
	
	override string toString(Context ctx, TypeQualifier qual) const {
		import std.algorithm, std.range;
		return returnType.toString(ctx, qual) ~ " delegate(" ~ paramTypes.map!(t => t.toString(ctx, qual)).join(", ") ~ (isVariadic?", ...) ":") ") ~ context.toString(ctx);
	}
}

alias AstDelegateType = DelegateType!AstType;

/**
 * Type defined by typeof(Expression)
 */
class TypeofType : AstType {
	AstExpression expression;
	
	this(AstExpression expression) {
		this.expression = expression;
	}
	
	override string toString(Context ctx, TypeQualifier) const {
		return "typeof(" ~ expression.toString(ctx) ~ ")";
	}
}

/**
 * Type defined by typeof(return)
 */
class ReturnType : AstType {
	override string toString(Context ctx, TypeQualifier) const {
		return "typeof(return)";
	}
}

