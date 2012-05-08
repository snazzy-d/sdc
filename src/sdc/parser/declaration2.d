module sdc.parser.declaration2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;
import sdc.parser.conditional2;
import sdc.parser.expression2;
import sdc.parser.identifier2;
import sdc.parser.statement2;
import sdc.parser.sdctemplate2;
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
	// TODO: move alias into the main switch.
	if(tstream.peek.type == TokenType.Alias) {
			return parseAlias(tstream);
	}
	
	auto location = tstream.peek.location;
	
	auto handleStorageClass(StorageClassDeclaration, U...)(U arguments) {
		switch(tstream.peek.type) {
			case TokenType.OpenBrace :
				auto declarations = parseAggregate(tstream);
				
				location.spanTo(tstream.previous.location);
				
				return new StorageClassDeclaration(location, arguments, declarations);
			
			case TokenType.Colon :
				tstream.get();
				auto declarations = parseAggregate!false(tstream);
				
				location.spanTo(tstream.previous.location);
				
				return new StorageClassDeclaration(location, arguments, declarations);
			
			default :
				return new StorageClassDeclaration(location, arguments, [parseDeclaration(tstream)]);
		}
	}
	
	Type type;
	
	switch(tstream.peek.type) {
		/*
		 * Auto declaration
		 */
		case TokenType.Identifier :
			// storageClass identifier = expression is an auto declaration.
			if(tstream.lookahead(1).type != TokenType.Assign) {
				// If it is not an auto declaration, this identifier is a type.
				goto default;
			}
			
			location.spanTo(tstream.previous.location);
			type = new AutoType(location);
			break;
			
		case TokenType.Auto :
			location.spanTo(tstream.get().location);
			type = new AutoType(location);
			
			break;
		
		/*
		 * Storage class
		 */
		case TokenType.Abstract :
			tstream.get();
			
			return handleStorageClass!AbstractDeclaration();
		
		case TokenType.Deprecated :
			tstream.get();
			
			return handleStorageClass!DeprecatedDeclaration();
		
		case TokenType.Nothrow :
			tstream.get();
			
			return handleStorageClass!NothrowDeclaration();
		
		case TokenType.Override :
			tstream.get();
			
			return handleStorageClass!OverrideDeclaration();
		
		case TokenType.Pure :
			tstream.get();
			
			return handleStorageClass!PureDeclaration();
		
		case TokenType.Static :
			tstream.get();
			
			// TODO: handle static if.
			
			return handleStorageClass!StaticDeclaration();
		
		case TokenType.Synchronized :
			tstream.get();
			
			return handleStorageClass!SynchronizedDeclaration();
		
		/*
		 * Visibility declaration
		 */
		case TokenType.Private :
			tstream.get();
			
			return handleStorageClass!PrivateDeclaration();
		
		case TokenType.Public :
			tstream.get();
			
			return handleStorageClass!PublicDeclaration();
		
		case TokenType.Protected :
			tstream.get();
			
			return handleStorageClass!ProtectedDeclaration();
		
		case TokenType.Package :
			tstream.get();
			
			return handleStorageClass!PackageDeclaration();
		
		case TokenType.Export :
			tstream.get();
			
			return handleStorageClass!ExportDeclaration();
		
		/*
		 * Linkage
		 */
		case TokenType.Extern :
			tstream.get();
			match(tstream, TokenType.OpenParen);
			string linkage = match(tstream, TokenType.Identifier).value;
			match(tstream, TokenType.CloseParen);
			
			return handleStorageClass!LinkageDeclaration(linkage);
		
		/*
		 * Class, interface and struct declaration
		 */
		case TokenType.Interface :
			// TODO: handle interfaces a proper way.
			goto case TokenType.Class;
		
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
		
		/*
		 * Constructor and destructor
		 */
		case TokenType.This :
			tstream.get();
			
			return parseFunction!(ConstructorDeclaration, ConstructorDefinition)(tstream, location);
		
		case TokenType.Tilde :
			tstream.get();
			match(tstream, TokenType.This);
			
			return parseFunction!(DestructorDeclaration, DestructorDefinition)(tstream, location);
		
		/*
		 * Template
		 */
		case TokenType.Template :
			return parseTemplate(tstream);
		
		/*
		 * Enum
		 */
		case TokenType.Enum :
			return parseEnum(tstream);
		
		/*
		 * Import
		 */
		case TokenType.Import :
			return parseImport(tstream);
		
		/*
		 * Conditional compilation
		 */
		case TokenType.Version :
			return parseVersion!Declaration(tstream);
		
		case TokenType.Debug :
			return parseVersion!Declaration(tstream);
		
		/*
		 * Variable and function declarations
		 */
		default :
			type = parseType(tstream);
	}
	
	if(tstream.lookahead(1).type == TokenType.OpenParen) {
		string name = match(tstream, TokenType.Identifier).value;
		
		return parseFunction!(FunctionDeclaration, FunctionDefinition)(tstream, location, name, type);
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
	
	auto tokenType = tstream.peek.type;
	while(tokenType != TokenType.CloseBrace && tokenType != TokenType.End) {
		declarations ~= parseDeclaration(tstream);
		tokenType = tstream.peek.type;
	}
	
	static if(globBraces) {
		match(tstream, TokenType.CloseBrace);
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
				assert(false, "Manifest constant must be parsed as auto declaration and not as enums.");
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
auto parseFunction(FunctionDeclarationType, FunctionDefinitionType, U... )(TokenStream tstream, Location location, U arguments) {
	// Function declaration.
	bool isVariadic;
	auto parameters = parseParameters(tstream, isVariadic);
	
	// TODO: parse function attributes
	// Parse function attributes
	functionAttributeLoop : while(1) {
		switch(tstream.peek.type) {
			case TokenType.Pure, TokenType.Const, TokenType.Immutable, TokenType.Mutable, TokenType.Inout, TokenType.Shared, TokenType.Nothrow :
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
			
			return new FunctionDeclarationType(location, arguments, parameters);
		
		case TokenType.OpenBrace :
			auto fbody = parseBlock(tstream);
			
			location.spanTo(tstream.peek.location);
			
			return new FunctionDefinitionType(location, arguments, parameters, fbody);
		
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

