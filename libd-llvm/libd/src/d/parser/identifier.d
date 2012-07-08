module d.parser.identifier;

import d.ast.identifier;

import d.parser.base;

import sdc.location;
import sdc.token;

import std.range;

/**
 * Parse Identifier
 */
auto parseIdentifier(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto location = trange.front.location;
	
	string name = trange.front.value;
	trange.match(TokenType.Identifier);
	
	return trange.parseBuiltIdentifier(location, new Identifier(location, name));
}

/**
 * Parse dotted identifier (.identifier)
 */
auto parseDotIdentifier(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
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
private auto parseBuiltIdentifier(TokenRange)(ref TokenRange trange, Location location, Identifier identifier) {
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
				auto lookahead = trange.save;
				lookahead.popFront();
				switch(lookahead.front.type) {
					case TokenType.OpenParen :
						// TODO: do something meaningful here.
						while(trange.front.type != TokenType.CloseParen) trange.popFront();
						trange.popFront();
						break;
					
					case TokenType.Identifier :
						trange.popFrontN(2);
						break;
					
					default :
						return identifier;
				}
				
				break;
			
			default :
				return identifier;
		}
	}
}

