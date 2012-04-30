module sdc.parser.declaration2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;
import sdc.parser.expression2;
import sdc.parser.identifier2;
import sdc.parser.statement2;
import sdc.parser.type2;
import sdc.ast.declaration2;
import sdc.ast.expression2;
import sdc.ast.identifier2;

/**
 * Parse a declaration
 */
Declaration parseDeclaration(TokenStream tstream) {
	// Parse alias declaration.
	while(tstream.peek.type == TokenType.Alias) {
			tstream.get();
			return parseAlias(tstream, tstream.previous.location);
	}
	
	// TODO: handle storage classes.
	
	string name;
	auto location = tstream.peek.location;
	
	switch(tstream.peek.type) {
		case TokenType.Identifier :
			// storageClass identifier = expression is an auto declaration.
			if(tstream.lookahead(1).type == TokenType.Assign) {
				// TODO: handle auto declaration.
			}
			
			assert(0);
		
		case TokenType.Class :
			tstream.get();
			
			name = match(tstream, TokenType.Identifier).value;
			Identifier[] bases;
			
			if(tstream.peek.type == TokenType.Colon) {
				do {
					tstream.get();
					bases ~= parseIdentifier(tstream);
				} while(tstream.peek.type == TokenType.Comma);
			}
			
			auto members = parseAggregate(tstream);
			
			location.spanTo(tstream.previous.location);
				
			return new ClassDefinition(location, name, bases, members);
		
		case TokenType.Struct :
			tstream.get();
			name = match(tstream, TokenType.Identifier).value;
			
			// Handle opaque structs.
			if(tstream.peek.type == TokenType.Semicolon) {
				location.spanTo(tstream.peek.location);
				
				tstream.get();
				
				return new StructDeclaration(location, name);
			} else {
				auto members = parseAggregate(tstream);
				
				location.spanTo(tstream.previous.location);
				
				return new StructDefinition(location, name, members);
			}
		
		case TokenType.Enum :
			// TODO: handle enum declaration.
			assert(0);
		
		case TokenType.Import :
			// TODO: handle imports.
			assert(0);
			
		default :
			// assert(0);
	}
	
	auto type = parseType(tstream);
	
	name = match(tstream, TokenType.Identifier).value;
	
	if(tstream.peek.type == TokenType.OpenParen) {
		// Function declaration.
		auto parameters = parseParameters(tstream);
		
		// TODO: parse member function attributes.
		// TODO: parse contracts.
		
		if(tstream.peek.type == TokenType.Semicolon) {
			location.spanTo(tstream.peek.location);
			
			tstream.get();
			
			return new FunctionDeclaration(location, name, type, parameters);
		} else {
			// Function with body
			auto fbody = parseBlock(tstream);
			
			location.spanTo(tstream.peek.location);
			
			return new FunctionDefinition(location, name, type, parameters, fbody);
		}
	} else {
		Expression[string] variables;
		
		// Variables declaration.
		void parseVariableDeclaration() {
			if(tstream.peek.type == TokenType.Assign) {
				tstream.get();
				
				variables[name] = parseInitializer(tstream);
			} else {
				// TODO: Use default initializer instead of null.
				variables[name] = null;
			}
		}
		
		parseVariableDeclaration();
		while(tstream.peek.type == TokenType.Comma) {
			name = match(tstream, TokenType.Identifier).value;
			parseVariableDeclaration();
		}
		
		location.spanTo(tstream.peek.location);
		match(tstream, TokenType.Semicolon);
		
		return new VariablesDeclaration(location, variables, type);
	}
}

/**
 * Parse alias declaration
 */
Declaration parseAlias(TokenStream tstream, Location location) {
	// Alias this (find a better way to dectect it to allow more complx identifiers ?).
	if(tstream.peek.type == TokenType.Identifier && tstream.lookahead(1).type == TokenType.This) {
		auto identifier = parseIdentifier(tstream);
		
		match(tstream, TokenType.This);
		location.spanTo(tstream.previous.location);
		
		return new AliasThisDeclaration(location, identifier);
	} else {
		auto type = parseBasicType(tstream);
		string name = match(tstream, TokenType.Identifier).value;
		
		location.spanTo(tstream.previous.location);
		
		return new AliasDeclaration(location, name, type);
	}
}

/**
 * Parse aggreagate (classes, structs)
 */
auto parseAggregate(TokenStream tstream) {
	match(tstream, TokenType.OpenBrace);
	
	Declaration[] declarations;
	
	while(tstream.peek.type != TokenType.CloseBrace) {
		declarations ~= parseDeclaration(tstream);
	}
	
	tstream.get();
	
	return declarations;
}

/**
 * Parse Initializer
 */
auto parseInitializer(TokenStream tstream) {
	// TODO: parse void initializer.
	return parseAssignExpression(tstream);
}

