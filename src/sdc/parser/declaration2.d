module sdc.parser.declaration2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;
import sdc.parser.expression2;
import sdc.parser.identifier2;
import sdc.parser.statement2;
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
	
	auto type = parseType(tstream);
	
	string name = match(tstream, TokenType.Identifier).value;
	
	if(tstream.peek.type == TokenType.OpenParen) {
		// Function declaration.
		auto parameters = parseParameters(tstream);
		
		// TODO: parse member function attributes.
		// TODO: parse contracts.
		
		if(tstream.peek.type == TokenType.Semicolon) {
			tstream.get();
			
			auto location = type.location;
			location.spanTo(tstream.peek.location);
			
			declarations ~= new FunctionDeclaration(location, name, type, parameters);
		} else {
			// Function with body
			auto fbody = parseBlock(tstream);
			
			auto location = type.location;
			location.spanTo(tstream.peek.location);
			
			declarations ~= new FunctionDefinition(location, name, type, parameters, fbody);
		}
	} else {
		// Variables declaration.
		auto location = type.location;
		
		void parseVariableDeclaration() {
			if(tstream.peek.type == TokenType.Assign) {
				tstream.get();
				auto value = parseInitializer(tstream);
			
				location.spanTo(tstream.peek.location);
			
				declarations ~= new InitializedVariableDeclaration(location, name, value);
			} else {
				location.spanTo(tstream.peek.location);
				declarations ~= new VariableDeclaration(location, name);
			}
		}
		
		parseVariableDeclaration();
		while(tstream.peek.type == TokenType.Comma) {
			name = match(tstream, TokenType.Identifier).value;
			parseVariableDeclaration();
		}
		
		match(tstream, TokenType.Semicolon);
	}
	
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

/**
 * Parse Initializer
 */
auto parseInitializer(TokenStream tstream) {
	// TODO: parse array and string literals.
	return parseAssignExpression(tstream);
}

