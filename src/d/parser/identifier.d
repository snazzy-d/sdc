module d.parser.identifier;

import d.ast.ambiguous;
import d.ast.identifier;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.type;

import d.parser.base;
import d.parser.dtemplate;

import std.range;

/**
 * Parse Identifier
 */
Identifier parseIdentifier(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto location = trange.front.location;
	
	string name = trange.front.value;
	trange.match(TokenType.Identifier);
	
	return trange.parseBuiltIdentifier(location, new BasicIdentifier(location, name));
}

/**
 * Parse dotted identifier (.identifier)
 */
Identifier parseDotIdentifier(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto location = trange.front.location;
	trange.match(TokenType.Dot);
	
	// FIXME: investigate why this don't compile.
	// location.spanTo(trange.front.location);
	
	string name = trange.front.value;
	trange.match(TokenType.Identifier);
	
	return trange.parseBuiltIdentifier(location, new DotIdentifier(location, name));
}

/**
 * Parse any qualifier identifier (qualifier.identifier)
 */
auto parseQualifiedIdentifier(TokenRange, Namespace)(ref TokenRange trange, Location location, Namespace ns) if(isTokenRange!TokenRange) {
	string name = trange.front.value;
	location.spanTo(trange.front.location);
	trange.match(TokenType.Identifier);
	
	static if(is(Namespace : Identifier)) {
		alias IdentifierDotIdentifier QualifiedIdentifier;
	} else static if(is(Namespace : Type)) {
		alias TypeDotIdentifier QualifiedIdentifier;
	} else static if(is(Namespace : Expression)) {
		alias ExpressionDotIdentifier QualifiedIdentifier;
	} else static if(is(Namespace : TypeOrExpression)) {
		alias AmbiguousDotIdentifier QualifiedIdentifier;
	} else {
		static assert(0, "Namespace can only be an Identifier, a Type, an Expression or a TypeOrExpression. Not a " ~ Namespace.stringof);
	}
	
	return trange.parseBuiltIdentifier(location, new QualifiedIdentifier(location, name, ns));
}

/**
 * Parse built identifier
 */
private Identifier parseBuiltIdentifier(TokenRange)(ref TokenRange trange, Location location, Identifier identifier) {
	while(1) {
		switch(trange.front.type) {
			case TokenType.Dot :
				trange.popFront();
				string name = trange.front.value;
				
				location.spanTo(trange.front.location);
				trange.match(TokenType.Identifier);
				
				identifier = new IdentifierDotIdentifier(location, name, identifier);
				break;
			
			// TODO: parse template instanciation.
			case TokenType.Bang :
				trange.popFront();
				auto arguments = parseTemplateArguments(trange);
				
				// XXX: is likely incorrect.
				location.spanTo(trange.front.location);
				
				auto instance = new TemplateInstanciation(location, identifier, arguments);
				
				if(trange.front.type == TokenType.Dot) {
					trange.popFront();
					
					string name = trange.front.value;
					
					location.spanTo(trange.front.location);
					trange.match(TokenType.Identifier);
					
					identifier = new TemplateInstanciationDotIdentifier(location, name, instance);
				} else {
					// TODO: create s pecial node for that ?
					identifier = new TemplateInstanciationDotIdentifier(location, identifier.name, instance);
				}
				
				break;
			
			default :
				return identifier;
		}
	}
}

