module d.parser.identifier;

import d.ast.identifier;
import d.ast.dtemplate;

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
	
	return trange.parseBuiltIdentifier(location, new Identifier(location, name));
}

/**
 * Parse dotted identifier (.identifier)
 */
Identifier parseDotIdentifier(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto location = trange.front.location;
	trange.match(TokenType.Dot);
	
	return trange.parseQualifiedIdentifier(location, new ModuleNamespace(location));
}

/**
 * Parse any qualifier identifier (qualifier.identifier)
 */
auto parseQualifiedIdentifier(TokenRange)(ref TokenRange trange, Location location, Namespace namespace) if(isTokenRange!TokenRange) {
	string name = trange.front.value;
	location.spanTo(trange.front.location);
	trange.match(TokenType.Identifier);
	
	return trange.parseBuiltIdentifier(location, new QualifiedIdentifier(location, name, namespace));
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
				
				identifier = new QualifiedIdentifier(location, name, identifier);
				break;
			
			// TODO: parse template instanciation.
			case TokenType.Bang :
				trange.popFront();
				auto arguments = parseTemplateArguments(trange);
				
				// TODO: is likely incorrect.
				location.spanTo(trange.front.location);
				
				identifier = new TemplateInstance(location, identifier, arguments);
				
				break;
			
			default :
				return identifier;
		}
	}
}

