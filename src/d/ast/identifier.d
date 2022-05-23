module d.ast.identifier;

import d.ast.declaration;
import d.ast.expression;
import d.ast.type;

import d.common.node;

import source.context;
import source.name;

abstract class Identifier : Node {
	this(Location location) {
		super(location);
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
	Name name;

	this(Location location, Name name) {
		super(location);

		this.name = name;
	}

	override string toString(const Context c) const {
		return name.toString(c);
	}
}

/**
 * An identifier qualified by an identifier (identifier.identifier)
 */
class IdentifierDotIdentifier : Identifier {
	Name name;
	Identifier identifier;

	this(Location location, Name name, Identifier identifier) {
		super(location);

		this.name = name;
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
	Name name;
	AstType type;

	this(Location location, Name name, AstType type) {
		super(location);

		this.name = name;
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
	Name name;
	AstExpression expression;

	this(Location location, Name name, AstExpression expression) {
		super(location);

		this.name = name;
		this.expression = expression;
	}

	override string toString(const Context c) const {
		return expression.toString(c) ~ "." ~ name.toString(c);
	}
}

/**
 * Template instantiation (identifier!(arguments...))
 */
class TemplateInstantiation : Identifier {
	Identifier identifier;
	AstTemplateArgument[] arguments;

	this(Location location, Identifier identifier,
	     AstTemplateArgument[] arguments) {
		super(location);

		this.identifier = identifier;
		this.arguments = arguments;
	}

	override string toString(const Context c) const {
		// Unfortunately, apply isn't const compliant so we cast it away.
		import std.algorithm, std.range;
		auto args = arguments.map!(a => (cast() a).apply!(a => a.toString(c)))
		                     .join(", ");
		return identifier.toString(c) ~ "!(" ~ args ~ ")";
	}
}

alias AstTemplateArgument = AstType.UnionType!(AstExpression, Identifier);

auto apply(alias handler)(AstTemplateArgument a) {
	alias Tag = typeof(a.tag);
	final switch (a.tag) with (Tag) {
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
	Name name;
	this(Location location, Name name) {
		super(location);

		this.name = name;
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
		super(location);

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
		super(location);

		this.indexed = indexed;
		this.index = index;
	}

	override string toString(const Context c) const {
		return indexed.toString(c) ~ "[" ~ index.toString(c) ~ "]";
	}
}
