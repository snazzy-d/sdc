module sdc.parser.identifier2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base;
import sdc.ast.identifier2;

/**
 * Parse Identifier
 */
auto parseIdentifier(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	string name = match(tstream, TokenType.Identifier).value;
	location.spanTo(tstream.previous.location);
	
	auto identifier = new Identifier(location, name);
	
	if(tstream.peek.type == TokenType.Dot) {
		tstream.get();
		identifier = parseQualifiedIdentifier(tstream, location, identifier);
	}
	
	return identifier;
}

/**
 * Parse dotted identifier (.identifier)
 */
auto parseDotIdentifier(TokenStream tstream, Location location) {
	return parseQualifiedIdentifier(tstream, location, new ModuleQualifier(location));
}

/**
 * Parse any qualifier identifier (qualifier.identifier)
 */
auto parseQualifiedIdentifier(TokenStream tstream, Location location, Qualifier qualifier) {
	string name = match(tstream, TokenType.Identifier).value;
	location.spanTo(tstream.previous.location);
	
	auto identifier = new QualifiedIdentifier(location, name, qualifier);
	
	while(tstream.peek.type == TokenType.Dot) {
		name = match(tstream, TokenType.Identifier).value;
		location.spanTo(tstream.previous.location);
		identifier = new QualifiedIdentifier(location, name, identifier);
	}
	
	return identifier;
}

