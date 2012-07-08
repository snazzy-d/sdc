module d.parser.declaration;

import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.parser.adt;
import d.parser.base;
import d.parser.conditional;
import d.parser.expression;
import d.parser.identifier;
import d.parser.statement;
import d.parser.dfunction;
import d.parser.dtemplate;
import d.parser.type;

import sdc.location;
import sdc.token;

import std.array;

/**
 * Parse a set of declarations.
 */
auto parseAggregate(bool globBraces = true, TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	static if(globBraces) {
		trange.match(TokenType.OpenBrace);
	}
	
	Declaration[] declarations;
	
	while(trange.front.type != TokenType.CloseBrace) {
		declarations ~= trange.parseDeclaration();
	}
	
	static if(globBraces) {
		trange.match(TokenType.CloseBrace);
	}
	
	return declarations;
}

/**
 * Parse a declaration
 */
Declaration parseDeclaration(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	Location location = trange.front.location;
	
	// TODO: bug repport and workaround : if trange is used, dmd explode.
	// To work around, the function is made static and all parameters passed manually. UFCS explode too.
	static auto handleStorageClass(StorageClassDeclaration, U...)(ref TokenRange trange, ref Location location, U arguments) {
		switch(trange.front.type) {
			case TokenType.OpenBrace :
				auto declarations = trange.parseAggregate();
				
				location.spanTo(declarations.back.location);
				
				return new StorageClassDeclaration(location, arguments, declarations);
			
			case TokenType.Colon :
				trange.popFront();
				auto declarations = trange.parseAggregate!false();
				
				location.spanTo(declarations.back.location);
				
				return new StorageClassDeclaration(location, arguments, declarations);
			
			default :
				return new StorageClassDeclaration(location, arguments, [trange.parseDeclaration()]);
		}
	}
	
	Type type;
	
	switch(trange.front.type) {
		/*
		 * Auto declaration
		 */
		case TokenType.Identifier :
			// storageClass identifier = expression is an auto declaration.
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type != TokenType.Assign) {
				// If it is not an auto declaration, this identifier is a type.
				goto default;
			}
			
			type = new AutoType(location);
			break;
		
		case TokenType.Auto :
			trange.popFront();
			type = new AutoType(location);
			
			break;
		
		/*
		 * Type qualifiers
		 */
		case TokenType.Const :
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == TokenType.Identifier) {
				lookahead.popFront();
				if(lookahead.front.type == TokenType.Assign) {
					trange.popFront();
					
					return handleStorageClass!ConstDeclaration(trange, location);
				}
			}
			
			goto default;
		
		case TokenType.Immutable :
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == TokenType.Identifier) {
				lookahead.popFront();
				if(lookahead.front.type == TokenType.Assign) {
					trange.popFront();
					
					return handleStorageClass!ImmutableDeclaration(trange, location);
				}
			}
			
			goto default;
		
		case TokenType.Inout :
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == TokenType.Identifier) {
				lookahead.popFront();
				if(lookahead.front.type == TokenType.Assign) {
					trange.popFront();
					
					return handleStorageClass!InoutDeclaration(trange, location);
				}
			}
			
			goto default;
		
		case TokenType.Shared :
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == TokenType.Identifier) {
				lookahead.popFront();
				if(lookahead.front.type == TokenType.Assign) {
					trange.popFront();
					
					return handleStorageClass!SharedDeclaration(trange, location);
				}
			}
			
			goto default;
		
		/*
		 * Storage class
		 */
		case TokenType.Abstract :
			trange.popFront();
			
			return handleStorageClass!AbstractDeclaration(trange, location);
		
		case TokenType.Deprecated :
			trange.popFront();
			
			return handleStorageClass!DeprecatedDeclaration(trange, location);
		
		case TokenType.Nothrow :
			trange.popFront();
			
			return handleStorageClass!NothrowDeclaration(trange, location);
		
		case TokenType.Override :
			trange.popFront();
			
			return handleStorageClass!OverrideDeclaration(trange, location);
		
		case TokenType.Pure :
			trange.popFront();
			
			return handleStorageClass!PureDeclaration(trange, location);
		
		case TokenType.Static :
			// Handle static if.
			// TODO: handle static assert.
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == TokenType.If) {
				return trange.parseStaticIf!Declaration();
			}
			
			trange.popFront();
			return handleStorageClass!StaticDeclaration(trange, location);
		
		case TokenType.Synchronized :
			trange.popFront();
			
			return handleStorageClass!SynchronizedDeclaration(trange, location);
		
		case TokenType.__Gshared :
			trange.popFront();
			
			return handleStorageClass!__GsharedDeclaration(trange, location);
		
		/*
		 * Visibility declaration
		 */
		case TokenType.Private :
			trange.popFront();
			
			return handleStorageClass!PrivateDeclaration(trange, location);
		
		case TokenType.Public :
			trange.popFront();
			
			return handleStorageClass!PublicDeclaration(trange, location);
		
		case TokenType.Protected :
			trange.popFront();
			
			return handleStorageClass!ProtectedDeclaration(trange, location);
		
		case TokenType.Package :
			trange.popFront();
			
			return handleStorageClass!PackageDeclaration(trange, location);
		
		case TokenType.Export :
			trange.popFront();
			
			return handleStorageClass!ExportDeclaration(trange, location);
		
		/*
		 * Linkage
		 */
		case TokenType.Extern :
			trange.popFront();
			trange.match(TokenType.OpenParen);
			string linkage = trange.front.value;
			trange.match(TokenType.Identifier);
			trange.match(TokenType.CloseParen);
			
			return handleStorageClass!LinkageDeclaration(trange, location, linkage);
		
		/**
		 * Attributes
		 */
		case TokenType.At :
			trange.popFront();
			string attribute = trange.front.value;
			trange.match(TokenType.Identifier);
			
			return handleStorageClass!AttributeDeclaration(trange, location, attribute);
		
		/*
		 * Class, interface, struct and union declaration
		 */
		case TokenType.Interface :
			return trange.parseInterface();
		
		case TokenType.Class :
			return trange.parseClass();
		
		case TokenType.Struct :
			return trange.parseStruct();
		
		case TokenType.Union :
			return trange.parseUnion();
		
		/*
		 * Constructor and destructor
		 */
		case TokenType.This :
			return trange.parseConstructor();
		
		case TokenType.Tilde :
			return trange.parseDestructor();
		
		/*
		 * Enum
		 */
		case TokenType.Enum :
			auto lookahead = trange.save;
			lookahead.popFront();
			
			// Determine if we are in case of manifest constant or regular enum.
			switch(lookahead.front.type) {
				case TokenType.Colon, TokenType.OpenBrace :
					return trange.parseEnum();
				
				case TokenType.Identifier :
					lookahead.popFront();
					switch(lookahead.front.type) {
						case TokenType.Colon, TokenType.OpenBrace :
							return trange.parseEnum();
						
						// Auto manifest constant declaration.
						case TokenType.Assign :
							trange.popFront();
							type = new AutoType(location);
							
							break;
						
						// We didn't recognize regular enums or manifest auto constant. Let's fallback to manifest typed constant.
						default :
							trange.popFront();
							type = trange.parseType();
							break;
					}
					
					break;
				
				default :
					trange.popFront();
					type = trange.parseType();
					break;
			}
			
			break;
		
		/*
		 * Template
		 */
		case TokenType.Template :
			return trange.parseTemplate();
		
		/*
		 * Import
		 */
		case TokenType.Import :
			return trange.parseImport();
		
		/**
		 * Alias
		 */
		case TokenType.Alias :
			return trange.parseAlias();
		
		/*
		 * Conditional compilation
		 */
		case TokenType.Version :
			return trange.parseVersion!Declaration();
		
		case TokenType.Debug :
			return trange.parseDebug!Declaration();
		
		case TokenType.Unittest :
			trange.popFront();
			trange.parseBlock();
			return null;
		
		/*
		 * Variable and function declarations
		 */
		default :
			type = trange.parseType();
	}
	
	auto lookahead = trange.save;
	lookahead.popFront();
	if(lookahead.front.type == TokenType.OpenParen) {
		string name = trange.front.value;
		trange.match(TokenType.Identifier);
		
		return trange.parseFunction(location, name, type);
	} else {
		VariableDeclaration[] variables;
		
		// Variables declaration.
		void parseVariableDeclaration() {
			string name = trange.front.value;
			Location variableLocation = trange.front.location;
			trange.match(TokenType.Identifier);
			
			Expression value;
			if(trange.front.type == TokenType.Assign) {
				trange.popFront();
				
				value = trange.parseInitializer();
				
				variableLocation.spanTo(value.location);
			}
			
			variables ~= new VariableDeclaration(location, type, name, value);
		}
		
		parseVariableDeclaration();
		while(trange.front.type == TokenType.Comma) {
			trange.popFront();
			
			parseVariableDeclaration();
		}
		
		location.spanTo(trange.front.location);
		trange.match(TokenType.Semicolon);
		
		return new VariablesDeclaration(location, variables);
	}
}

/**
 * Parse alias declaration
 */
private Declaration parseAlias(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	trange.match(TokenType.Alias);
	
	// Alias this (find a better way to dectect it to allow more complx identifiers ?).
	if(trange.front.type == TokenType.Identifier) {
		auto lookahead = trange.save;
		lookahead.popFront();
		if(lookahead.front.type == TokenType.This) {
			auto identifier = trange.parseIdentifier();
			
			trange.match(TokenType.This);
			location.spanTo(trange.front.location);
			trange.match(TokenType.Semicolon);
			
			return new AliasThisDeclaration(location, identifier);
		}
	}
	
	auto type = trange.parseType();
	string name = trange.front.value;
	trange.match(TokenType.Identifier);
	
	location.spanTo(trange.front.location);
	trange.match(TokenType.Semicolon);
	
	return new AliasDeclaration(location, name, type);
}

/**
 * Parse import declaration
 */
private auto parseImport(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	trange.match(TokenType.Import);
	
	Identifier[] modules = [trange.parseIdentifier()];
	while(trange.front.type == TokenType.Comma) {
		trange.popFront();
		modules ~= trange.parseIdentifier();
	}
	
	location.spanTo(trange.front.location);
	trange.match(TokenType.Semicolon);
	
	return new ImportDeclaration(location, modules);
}

/**
 * Parse Initializer
 */
private auto parseInitializer(TokenRange)(ref TokenRange trange) {
	if(trange.front.type == TokenType.Void) {
		auto location = trange.front.location;
		
		trange.popFront();
		
		return new VoidInitializer(location);
	}
	
	return trange.parseAssignExpression();
}

