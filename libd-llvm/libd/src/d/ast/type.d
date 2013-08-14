module d.ast.type;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.qualtype;

abstract class AstType {
	final override string toString() {
		return toString(TypeQualifier.Mutable);
	}
	
	string toString(TypeQualifier) const {
		assert(0, "Not implemented");
	}
}

alias QualAstType = QualType!AstType;
alias ParamAstType = ParamType!AstType;

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
	
	override string toString(TypeQualifier) const {
		return "";
		// return identifier.toString();
	}
}

/**
 * Pointer type
 */
class PointerType(T) if(is(T : AstType)) : T {
	QualType!T pointed;
	
	this(QualType!T pointed) {
		this.pointed = pointed;
	}
	
	override string toString(TypeQualifier qual) const {
		return pointed.toString(qual) ~ "*";
	}
	
	invariant() {
		assert(pointed.type);
	}
}

alias AstPointerType = PointerType!AstType;

/**
 * Slice type
 */
class SliceType(T) if(is(T : AstType)) : T {
	QualType!T sliced;
	
	this(QualType!T sliced) {
		this.sliced = sliced;
	}
	
	override string toString(TypeQualifier qual) const {
		return sliced.toString(qual) ~ "[]";
	}
	
	invariant() {
		assert(sliced.type);
	}
}

alias AstSliceType = SliceType!AstType;

/**
 * Associative array type
 */
class AssociativeArrayType(T) if(is(T : AstType)) : T {
	QualType!T keyType;
	QualType!T elementType;
	
	this(QualType!T keyType, QualType!T elementType) {
		this.keyType = keyType;
		this.elementType = elementType;
	}
	
	override string toString(TypeQualifier qual) const {
		return elementType.toString(qual) ~ "[" ~ keyType.toString(qual) ~ "]";
	}
}

alias AstAssociativeArrayType = AssociativeArrayType!AstType;

/**
 * Static array types
 */
class ArrayType : AstType {
	QualAstType elementType;
	AstExpression size;
	
	this(QualAstType elementType, AstExpression size) {
		this.elementType = elementType;
		this.size = size;
	}
	
	override string toString(TypeQualifier qual) const {
		return elementType.toString(qual) ~ "[" ~ size.toString() ~ "]";
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
	
	override string toString(TypeQualifier qual) const {
		return elementType.toString(qual) ~ "[" ~ identifier.toString() ~ "]";
	}
}

/**
 * Function types
 */
class FunctionType(T) if(is(T : AstType)) : T {
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
	
	override string toString(TypeQualifier qual) const {
		import std.algorithm, std.range;
		return returnType.toString(qual) ~ " function(" ~ paramTypes.map!(t => t.toString(qual)).join(", ") ~ (isVariadic?", ...)":")");
	}
}

alias AstFunctionType = FunctionType!AstType;
alias QualAstFunctionType = QualType!AstFunctionType;

/**
 * Delegate types
 */
class DelegateType(T) if(is(T : AstType)) : T {
	ParamType!T returnType;
	ParamType!T context;
	ParamType!T[] paramTypes;
	
	import std.bitmanip;
	mixin(bitfields!(
		Linkage, "linkage", 3,
		bool, "isVariadic", 1,
		uint, "", 4,
	));
	
	this(Linkage linkage,  ParamType!T returnType,  ParamType!T context, ParamType!T[] paramTypes, bool isVariadic) {
		this.returnType = returnType;
		this.context = context;
		this.paramTypes = paramTypes;
		this.linkage = linkage;
		this.isVariadic = isVariadic;
	}
	
	this(FunctionType!T t) {
		returnType = t.returnType;
		context = t.paramTypes[0];
		paramTypes = t.paramTypes[1 .. $];
		linkage = t.linkage;
		isVariadic = t.isVariadic;
	}
	
	override string toString(TypeQualifier qual) const {
		import std.algorithm, std.range;
		return returnType.toString(qual) ~ " delegate(" ~ paramTypes.map!(t => t.toString(qual)).join(", ") ~ (isVariadic?", ...)":")");
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
	
	override string toString(TypeQualifier) const {
		return "typeof(" ~ expression.toString() ~ ")";
	}
}

/**
 * Type defined by typeof(return)
 */
class ReturnType : AstType {
	override string toString(TypeQualifier) const {
		return "typeof(return)";
	}
}

