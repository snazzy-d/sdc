module d.parser.identifier;

import d.ast.identifier;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

/**
 * Parse Identifier
 */
auto parseIdentifier(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	string name = match(tstream, TokenType.Identifier).value;
	location.spanTo(tstream.previous.location);
	
	return parseBuiltIdentifier(tstream, location, new Identifier(location, name));
}

/**
 * Parse dotted identifier (.identifier)
 */
auto parseDotIdentifier(TokenStream tstream) {
	auto location = match(tstream, TokenType.Dot).location;
	return parseQualifiedIdentifier(tstream, location, new ModuleNamespace(location));
}

/**
 * Parse any qualifier identifier (qualifier.identifier)
 */
auto parseQualifiedIdentifier(TokenStream tstream, Location location, Namespace namespace) {
	string name = match(tstream, TokenType.Identifier).value;
	location.spanTo(tstream.previous.location);
	
	return parseBuiltIdentifier(tstream, location, new QualifiedIdentifier(location, name, namespace));
}

/**
 * Parse built identifier
 */
private
auto parseBuiltIdentifier(TokenStream tstream, Location location, Identifier identifier) {
	while(1) {
		switch(tstream.peek.type) {
			case TokenType.Dot :
				tstream.get();
				string name = match(tstream, TokenType.Identifier).value;
				location.spanTo(tstream.previous.location);
				
				identifier = new QualifiedIdentifier(location, name, identifier);
				break;
			
			// TODO: parse template instanciation.
			case TokenType.Bang :
				tstream.get();
				if(tstream.peek.type == TokenType.OpenParen) {
					// TODO: do something meaningful here.
					while(tstream.get().type != TokenType.CloseParen) tstream.get();
				} else {
					// TODO: Parse different types of unique template argument.
					match(tstream, TokenType.Identifier);
				}
				
				break;
			
			default :
				return identifier;
		}
	}
}

