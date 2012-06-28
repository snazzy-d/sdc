module d.parser.declaration;

import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.parser.adt;
import d.parser.conditional;
import d.parser.expression;
import d.parser.identifier;
import d.parser.statement;
import d.parser.dfunction;
import d.parser.dtemplate;
import d.parser.type;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

/**
 * Parse a set of declarations.
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
 * Parse a declaration
 */
Declaration parseDeclaration(TokenStream tstream) {
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
			// Handle static if.
			if(tstream.lookahead(1).type == TokenType.If) {
				return parseStaticIf!Declaration(tstream);
			}
			
			tstream.get();
			return handleStorageClass!StaticDeclaration();
		
		case TokenType.Synchronized :
			tstream.get();
			
			return handleStorageClass!SynchronizedDeclaration();
		
		case TokenType.__Gshared :
			tstream.get();
			
			return handleStorageClass!__GsharedDeclaration();
		
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
		
		/**
		 * Attributes
		 */
		case TokenType.At :
			tstream.get();
			string attribute = match(tstream, TokenType.Identifier).value;
			
			return handleStorageClass!AttributeDeclaration(attribute);
		
		/*
		 * Class, interface, struct and union declaration
		 */
		case TokenType.Interface :
			return parseInterface(tstream);
		
		case TokenType.Class :
			return parseClass(tstream);
		
		case TokenType.Struct :
			return parseStruct(tstream);
		
		case TokenType.Union :
			return parseUnion(tstream);
		
		/*
		 * Constructor and destructor
		 */
		case TokenType.This :
			return parseConstructor(tstream);
		
		case TokenType.Tilde :
			return parseDestructor(tstream);
		
		/*
		 * Enum
		 */
		case TokenType.Enum :
			// Determine if we are in case of manifest constant or regular enum.
			switch(tstream.lookahead(1).type) {
				case TokenType.Colon, TokenType.OpenBrace :
					return parseEnum(tstream);
				
				case TokenType.Identifier :
					switch(tstream.lookahead(2).type) {
						case TokenType.Colon, TokenType.OpenBrace :
							return parseEnum(tstream);
						
						// Auto manifest constant declaration.
						case TokenType.Assign :
							tstream.get();
							location.spanTo(tstream.previous.location);
							type = new AutoType(location);
							
							break;
						
						// We didn't recognize regular enums or manifest auto constant. Let's fallback to manifest typed constant.
						default :
							tstream.get();
							type = parseType(tstream);
							break;
					}
					
					break;
				
				default :
					tstream.get();
					type = parseType(tstream);
					break;
			}
			
			break;
		
		/*
		 * Template
		 */
		case TokenType.Template :
			return parseTemplate(tstream);
		
		/*
		 * Import
		 */
		case TokenType.Import :
			return parseImport(tstream);
		
		/**
		 * Alias
		 */
		case TokenType.Alias :
			return parseAlias(tstream);
		
		/*
		 * Conditional compilation
		 */
		case TokenType.Version :
			return parseVersion!Declaration(tstream);
		
		case TokenType.Debug :
			return parseVersion!Declaration(tstream);
		
		case TokenType.Unittest :
			tstream.get();
			parseBlock(tstream);
			return null;
		
		/*
		 * Variable and function declarations
		 */
		default :
			type = parseType(tstream);
	}
	
	if(tstream.lookahead(1).type == TokenType.OpenParen) {
		string name = match(tstream, TokenType.Identifier).value;
		
		return parseFunction(tstream, location, name, type);
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
		
		return new VariablesDeclaration(location, type, variables);
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
 * Parse Initializer
 */
auto parseInitializer(TokenStream tstream) {
	// TODO: parse void initializer.
	return parseAssignExpression(tstream);
}

