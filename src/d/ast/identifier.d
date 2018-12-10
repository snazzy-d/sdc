module d.ast.identifier;

import d.ast.declaration;
import d.ast.expression;
import d.ast.type;

import d.common.node;

import d.context.context;
import d.context.name;

abstract class Identifier : Node {
	Name name;
	
	this(Location location, Name name) {
		super(location);
		
		this.name = name;
	}
	
	string toString(const Context c) const {
		assert(0, "toString not implement for " ~ typeid(this).toString());
	}
}

final:
/**
 * An identifier.
 */
class BasicIdentifier : Identifier {
	this(Location location, Name name) {
		super(location, name);
	}
	
	override string toString(const Context c) const {
		return name.toString(c);
	}
}

/**
 * An identifier qualified by an identifier (identifier.identifier)
 */
class IdentifierDotIdentifier : Identifier {
	Identifier identifier;
	
	this(Location location, Name name, Identifier identifier) {
		super(location, name);
		
		this.identifier = identifier;
	}
	
	override string toString(const Context c) const {
		return identifier.toString(c) ~ "." ~ name.toString(c);
	}
}

/**
 * An identifier qualified by a type (type.identifier)
 */
class TypeDotIdentifier : Identifier {
	AstType type;
	
	this(Location location, Name name, AstType type) {
		super(location, name);
		
		this.type = type;
	}
	
	override string toString(const Context c) const {
		return type.toString(c) ~ "." ~ name.toString(c);
	}
}

/**
 * An identifier qualified by an expression (expression.identifier)
 */
class ExpressionDotIdentifier : Identifier {
	AstExpression expression;
	
	this(Location location, Name name, AstExpression expression) {
		super(location, name);
		
		this.expression = expression;
	}
	
	override string toString(const Context c) const {
		return expression.toString(c) ~ "." ~ name.toString(c);
	}
}

/**
 * An identifier qualified by a template (template!(...).identifier)
 */
class TemplateInstantiationDotIdentifier : Identifier {
	TemplateInstantiation instanciation;
	
	this(Location location, Name name, TemplateInstantiation instanciation) {
		super(location, name);
		
		this.instanciation = instanciation;
	}
	
	override string toString(const Context c) const {
		return instanciation.toString(c) ~ "." ~ name.toString(c);
	}
}

/**
 * Template instantiation
 */
class TemplateInstantiation : Node {
	Identifier identifier;
	AstTemplateArgument[] arguments;
	
	this(
		Location location,
		Identifier identifier,
		AstTemplateArgument[] arguments,
	) {
		super(location);
		
		this.identifier = identifier;
		this.arguments = arguments;
	}
	
	string toString(const Context c) const {
		// Unfortunately, apply isn't const compliant so we cast it away.
		import std.algorithm, std.range;
		auto args = arguments
			.map!(a => (cast() a).apply!(a => a.toString(c)))
			.join(", ");
		return identifier.toString(c) ~ "!(" ~ args ~ ")";
	}
}

alias AstTemplateArgument = AstType.UnionType!(AstExpression, Identifier);

auto apply(alias handler)(AstTemplateArgument a) {
	alias Tag = typeof(a.tag);
	final switch(a.tag) with(Tag) {
		case AstExpression:
			return handler(a.get!AstExpression);
		
		case Identifier:
			return handler(a.get!Identifier);
		
		case AstType:
			return handler(a.get!AstType);
	}
}

/**
 * A module level identifier (.identifier)
 */
class DotIdentifier : Identifier {
	this(Location location, Name name) {
		super(location, name);
	}
	
	override string toString(const Context c) const {
		return "." ~ name.toString(c);
	}
}

/**
 * An identifier of the form identifier[identifier]
 */
class IdentifierBracketIdentifier : Identifier {
	Identifier indexed;
	Identifier index;
	
	this(Location location, Identifier indexed, Identifier index) {
		super(location, indexed.name);
		
		this.indexed = indexed;
		this.index = index;
	}
	
	override string toString(const Context c) const {
		return indexed.toString(c) ~ "[" ~ index.toString(c) ~ "]";
	}
}

/**
 * An identifier of the form identifier[expression]
 */
class IdentifierBracketExpression : Identifier {
	Identifier indexed;
	AstExpression index;
	
	this(Location location, Identifier indexed, AstExpression index) {
		super(location, indexed.name);
		
		this.indexed = indexed;
		this.index = index;
	}
	
	override string toString(const Context c) const {
		return indexed.toString(c) ~ "[" ~ index.toString(c) ~ "]";
	}
}
