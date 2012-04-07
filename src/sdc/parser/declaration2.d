module sdc.parser.declaration2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;
import sdc.parser.identifier2;
import sdc.parser.type2;
import sdc.ast.declaration2;
import sdc.ast.identifier2;

/**
 * Parse a declaration
 */
auto parseDeclaration(TokenStream tstream) {
	auto location = tstream.peek.location;
	
	switch(tstream.peek.type) {
		case TokenType.Alias :
			tstream.get();
			return parseAlias(tstream, location);
		default :
			assert(0);
	}
}

/**
 * Parse alias declaration
 */
auto parseAlias(TokenStream tstream, Location location) {
	Declaration declaration;
	
	// Alias this (find a better way to dectect it to allow more complx identifiers ?).
	if(tstream.peek.type == TokenType.Identifier && tstream.lookahead(1).type == TokenType.This) {
		auto identifier = parseIdentifier(tstream);
		
		match(tstream, TokenType.This);
		location.spanTo(tstream.previous.location);
		
		declaration = new AliasThisDeclaration(location, identifier);
	} else {
		auto type = parseBasicType(tstream);
		string name = match(tstream, TokenType.Identifier).value;
		auto identifier = new Identifier(tstream.previous.location, name);
		
		location.spanTo(tstream.previous.location);
		
		declaration = new AliasDeclaration(location, identifier, type);
	}
	
	return declaration;
}

