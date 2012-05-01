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
import sdc.ast.type2;

/**
 * Parse a declaration
 */
Declaration parseDeclaration(TokenStream tstream) {
	// Parse alias declaration.
	if(tstream.peek.type == TokenType.Alias) {
			return parseAlias(tstream);
	}
	
	// TODO: handle storage classes.
	// TODO: handle linkage.
	
	auto location = tstream.peek.location;
	
	switch(tstream.peek.type) {
		case TokenType.Identifier :
			// storageClass identifier = expression is an auto declaration.
			if(tstream.lookahead(1).type == TokenType.Assign) {
				// TODO: handle auto declaration.
			}
			
			match(tstream, TokenType.Begin);
			assert(0);
		
		case TokenType.Class :
			tstream.get();
			
			string name = match(tstream, TokenType.Identifier).value;
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
			string name = match(tstream, TokenType.Identifier).value;
			
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
			match(tstream, TokenType.Begin);
			assert(0);
		
		case TokenType.Import :
			return parseImport(tstream);
			
		default :
			break;
	}
	
	auto type = parseType(tstream);
	
	if(tstream.lookahead(1).type == TokenType.OpenParen) {
		return parseFunctionDeclaration(tstream, location, type);
	} else {
		Expression[string] variables;
		
		// Variables declaration.
		void parseVariableDeclaration() {
			string name = match(tstream, TokenType.Identifier).value;
			
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
			tstream.get();
			
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
Declaration parseAlias(TokenStream tstream) {
	auto location = match(tstream, TokenType.Alias).location;
	
	// Alias this (find a better way to dectect it to allow more complx identifiers ?).
	if(tstream.peek.type == TokenType.Identifier && tstream.lookahead(1).type == TokenType.This) {
		auto identifier = parseIdentifier(tstream);
		
		match(tstream, TokenType.This);
		location.spanTo(match(tstream, TokenType.Semicolon).location);
		
		return new AliasThisDeclaration(location, identifier);
	} else {
		auto type = parseBasicType(tstream);
		string name = match(tstream, TokenType.Identifier).value;
		
		location.spanTo(match(tstream, TokenType.Semicolon).location);
		
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
 * Parse import declaration
 */
auto parseImport(TokenStream tstream) {
	auto location = match(tstream, TokenType.Import).location;
	
	Identifier[] modules = [parseIdentifier(tstream)];
	while(tstream.peek.type == TokenType.Comma) {
		tstream.get();
		modules ~= parseIdentifier(tstream);
	}
	
	match(tstream, TokenType.Semicolon);
	
	location.spanTo(tstream.previous.location);
	
	return new ImportDeclaration(location, modules);
}

/**
 * Parse function declaration
 */
auto parseFunctionDeclaration(TokenStream tstream, Location location, Type returnType) {
	string name = match(tstream, TokenType.Identifier).value;
	
	// Function declaration.
	auto parameters = parseParameters(tstream);
	
	// TODO: parse member function attributes.
	// TODO: parse contracts.
	
	// Skip contracts
	switch(tstream.peek.type) {
		case TokenType.In, TokenType.Out :
			tstream.get();
			parseBlock(tstream);
			
			switch(tstream.peek.type) {
				case TokenType.In, TokenType.Out :
					tstream.get();
					parseBlock(tstream);
					break;
				
				default :
					break;
			}
			
			break;
		
		default :
			break;
	}
	
	switch(tstream.peek.type) {
		case TokenType.Semicolon :
			location.spanTo(tstream.peek.location);
			tstream.get();
			
			return new FunctionDeclaration(location, name, returnType, parameters);
		
		case TokenType.Body :
			// Body without contract is just skipped.
			tstream.get();
			goto case TokenType.OpenBrace;
		
		case TokenType.OpenBrace :
			auto fbody = parseBlock(tstream);
			
			location.spanTo(tstream.peek.location);
			
			return new FunctionDefinition(location, name, returnType, parameters, fbody);
		
		default :
			// TODO: error.
			match(tstream, TokenType.Begin);
			assert(0);
	}
}

/**
 * Parse Initializer
 */
auto parseInitializer(TokenStream tstream) {
	// TODO: parse void initializer.
	return parseAssignExpression(tstream);
}

