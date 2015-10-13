module d.parser.identifier;

import d.ast.identifier;
import d.ast.expression;
import d.ast.type;

import d.parser.base;
import d.parser.dtemplate;

/**
 * Parse Identifier
 */
Identifier parseIdentifier(ref TokenRange trange) {
	auto location = trange.front.location;
	
	auto name = trange.front.name;
	trange.match(TokenType.Identifier);
	
	return trange.parseBuiltIdentifier(location, new BasicIdentifier(location, name));
}

/**
 * Parse dotted identifier (.identifier)
 */
Identifier parseDotIdentifier(ref TokenRange trange) {
	auto location = trange.front.location;
	trange.match(TokenType.Dot);
	
	// FIXME: investigate why this don't compile.
	// location.spanTo(trange.front.location);
	
	auto name = trange.front.name;
	trange.match(TokenType.Identifier);
	
	return trange.parseBuiltIdentifier(location, new DotIdentifier(location, name));
}

/**
 * Parse any qualifier identifier (qualifier.identifier)
 */
auto parseQualifiedIdentifier(Namespace)(ref TokenRange trange, Location location, Namespace ns) {
	auto name = trange.front.name;
	location.spanTo(trange.front.location);
	trange.match(TokenType.Identifier);
	
	static if (is(Namespace : Identifier)) {
		alias QualifiedIdentifier = IdentifierDotIdentifier;
	} else static if (is(Namespace : AstType)) {
		alias QualifiedIdentifier = TypeDotIdentifier;
	} else static if (is(Namespace : AstExpression)) {
		alias QualifiedIdentifier = ExpressionDotIdentifier;
	} else {
		static assert(0, "Namespace can only be an Identifier, a AstType or an Expression. Not a " ~ Namespace.stringof);
	}
	
	return trange.parseBuiltIdentifier(location, new QualifiedIdentifier(location, name, ns));
}

/**
 * Parse built identifier
 */
private Identifier parseBuiltIdentifier(ref TokenRange trange, Location location, Identifier identifier) {
	while(1) {
		switch(trange.front.type) with(TokenType) {
			case Dot :
				trange.popFront();
				auto name = trange.front.name;
				
				location.spanTo(trange.front.location);
				trange.match(Identifier);
				
				identifier = new IdentifierDotIdentifier(location, name, identifier);
				break;
			
			case Bang :
				auto lookahead = trange.save;
				lookahead.popFront();
				if (lookahead.front.type == Is || lookahead.front.type == In) {
					return identifier;
				}
				
				trange.popFront();
				auto arguments = parseTemplateArguments(trange);
				
				// XXX: is likely incorrect.
				location.spanTo(trange.front.location);
				
				auto instance = new TemplateInstanciation(location, identifier, arguments);
				
				if (trange.front.type != Dot) {
					// TODO: create s pecial node for that ?
					identifier = new TemplateInstanciationDotIdentifier(location, identifier.name, instance);
					break;
				}
				
				trange.popFront();
				
				auto name = trange.front.name;
				
				location.spanTo(trange.front.location);
				trange.match(Identifier);
				
				identifier = new TemplateInstanciationDotIdentifier(location, name, instance);
				break;
			
			default :
				return identifier;
		}
	}
}
