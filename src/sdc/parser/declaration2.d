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
// TODO: handle linkage.
Declaration parseDeclaration(TokenStream tstream) {
	// Parse alias declaration.
	if(tstream.peek.type == TokenType.Alias) {
			return parseAlias(tstream);
	}
	
	auto location = tstream.peek.location;
	
	// TODO: handle storage classes.
	storageClassLoop : while(1) {
		switch(tstream.peek.type) {
			case TokenType.Static :
				tstream.get();
				break;
			
			case TokenType.Extern :
				tstream.get();
				match(tstream, TokenType.OpenParen);
				string linkage = match(tstream, TokenType.Identifier).value;
				match(tstream, TokenType.CloseParen);
				
				switch(tstream.peek.type) {
					case TokenType.OpenBrace :
						auto declarations = parseAggregate(tstream);
						
						location.spanTo(tstream.previous.location);
						
						return new LinkageDeclaration(location, linkage, declarations);
					
					case TokenType.Colon :
						tstream.get();
						auto declarations = parseAggregate!false(tstream);
						
						location.spanTo(tstream.previous.location);
						
						return new LinkageDeclaration(location, linkage, declarations);
					
					default :
						// TODO: Change linkage and parse the next declaration.
						break;
				}
				
				break;
			
			default :
				break storageClassLoop;
		}
	}
	
	switch(tstream.peek.type) {
		case TokenType.Identifier :
			// storageClass identifier = expression is an auto declaration.
			if(tstream.lookahead(1).type == TokenType.Assign) {
				// TODO: handle auto declaration.
			}
			
			// If it is not an auto declaration, this identifier is a type.
			break;
		
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
			return parseEnum(tstream);
		
		case TokenType.Import :
			return parseImport(tstream);
		
		case TokenType.Version :
			return parseVersionDeclaration(tstream);
		
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
		auto type = parseType(tstream);
		string name = match(tstream, TokenType.Identifier).value;
		
		location.spanTo(match(tstream, TokenType.Semicolon).location);
		
		return new AliasDeclaration(location, name, type);
	}
}

/**
 * Parse aggreagate (classes, structs)
 */
auto parseAggregate(bool globBraces = true)(TokenStream tstream) {
	static if(globBraces) {
		match(tstream, TokenType.OpenBrace);
	}
	
	Declaration[] declarations;
	
	while(tstream.peek.type != TokenType.CloseBrace) {
		declarations ~= parseDeclaration(tstream);
	}
	
	static if(globBraces) {
		tstream.get();
	}
	
	return declarations;
}

/**
 * Parse enums
 */
auto parseEnum(TokenStream tstream) {
	auto location = match(tstream, TokenType.Enum).location;
	
	switch(tstream.peek.type) {
		case TokenType.Identifier :
			string name = tstream.get().value;
			
			// Check if we are in case of manifest constant.
			if(tstream.peek.type == TokenType.Assign) {
				// Parse auto declaration.
			}
			
			// TODO: named enums.
			// TODO: handle name AND typed enums.
			if(tstream.peek.type == TokenType.Colon) goto case TokenType.Colon;
			
			break;
		
		case TokenType.Colon :
			tstream.get();
			auto type = parseType(tstream);
			
			// TODO: typed enums.
			break;
		
		case TokenType.OpenBrace :
			break;
		
		default :
			assert(0);
	}
	
	match(tstream, TokenType.OpenBrace);
	
	while(tstream.peek.type != TokenType.OpenBrace) {
		string name = match(tstream, TokenType.Identifier).value;
		
		if(tstream.peek.type == TokenType.Assign) {
			tstream.get();
			parseAssignExpression(tstream);
		}
		
		if(tstream.peek.type == TokenType.Comma) {
			tstream.get();
		} else {
			// If it is not a comma, then we abort the loop.
			break;
		}
	}
	
	match(tstream, TokenType.CloseBrace);
	
	return null;
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
	bool isVariadic;
	auto parameters = parseParameters(tstream, isVariadic);
	
	// TODO: parse function attributes
	// Parse function attributes
	functionAttributeLoop : while(1) {
		switch(tstream.peek.type) {
			case TokenType.Pure, TokenType.Const, TokenType.Immutable, TokenType.Mutable, TokenType.Inout, TokenType.Shared :
				tstream.get();
				break;
			
			case TokenType.At :
				tstream.get();
				match(tstream, TokenType.Identifier);
				break;
			
			default :
				break functionAttributeLoop;
		}
	}
	
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
			
			match(tstream, TokenType.Body);
			break;
		
		case TokenType.Body :
			// Body without contract is just skipped.
			tstream.get();
			break;
		
		default :
			break;
	}
	
	switch(tstream.peek.type) {
		case TokenType.Semicolon :
			location.spanTo(tstream.peek.location);
			tstream.get();
			
			return new FunctionDeclaration(location, name, returnType, parameters);
		
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
 * Parse Version Declaration
 */
auto parseVersionDeclaration(TokenStream tstream) {
	auto location = match(tstream, TokenType.Version).location;
	
	switch(tstream.peek.type) {
		case TokenType.OpenParen :
			tstream.get();
			string versionId = match(tstream, TokenType.Identifier).value;
			match(tstream, TokenType.CloseParen);
			
			if(tstream.peek.type == TokenType.OpenBrace) {
				parseAggregate(tstream);
			} else {
				parseDeclaration(tstream);
			}
			
			if(tstream.peek.type == TokenType.Else) {
				tstream.get();
				if(tstream.peek.type == TokenType.OpenBrace) {
					parseAggregate(tstream);
				} else {
					parseDeclaration(tstream);
				}
			}
			
			return null;
		
		case TokenType.Assign :
			tstream.get();
			string foobar = match(tstream, TokenType.Identifier).value;
			match(tstream, TokenType.Semicolon);
			
			return null;
		
		default :
			// TODO: error.
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

