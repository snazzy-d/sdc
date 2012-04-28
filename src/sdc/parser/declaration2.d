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
auto parseDeclarations(TokenStream tstream) {
	Declaration[] declarations;
	
	// Parse alias declaration.
	while(tstream.peek.type == TokenType.Alias) {
			tstream.get();
			declarations ~= parseAlias(tstream, tstream.previous.location);
	}
	
	// TODO: handle storage classes.
	
	switch(tstream.peek.type) {
		case TokenType.Identifier :
			// storageClass identifier = expression is an auto declaration.
			if(tstream.lookahead(1).type == TokenType.Assign) {
				// TODO: handle auto declaration.
			}
			
			assert(0);
		
		case TokenType.Class :
			// TODO: handle class declaration.
			assert(0);
		
		case TokenType.Struct :
			// TODO: handle struct declaration.
			assert(0);
		
		case TokenType.Enum :
			// TODO: handle enum declaration.
			assert(0);
		
		default :
			// assert(0);
	}
	
	// TODO: handle class, struct and templates declarations.
	
	auto type = parseType(tstream);
	
	string name = match(tstream, TokenType.Identifier).value;
	auto identifier = new Identifier(tstream.previous.location, name);
	
	// Function declaration.
	if(tstream.peek.type == TokenType.OpenParen) {
		assert(0);
	}
	
	// TODO: Variable declaration.
	
	return declarations;
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
		
		location.spanTo(tstream.previous.location);
		
		declaration = new AliasDeclaration(location, name, type);
	}
	
	return declaration;
}

