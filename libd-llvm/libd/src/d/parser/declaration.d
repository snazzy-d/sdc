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

/**
 * Parse a set of declarations.
 */
auto parseAggregate(bool globBraces = true, R)(ref R trange) if(isTokenRange!R) {
	static if(globBraces) {
		trange.match(TokenType.OpenBrace);
	}
	
	Declaration[] declarations;
	
	while(!trange.empty && trange.front.type != TokenType.CloseBrace) {
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
Declaration parseDeclaration(R)(ref R trange) if(isTokenRange!R) {
	Location location = trange.front.location;
	
	auto handleStorageClass(StorageClassDeclaration, U...)(U arguments) {
		Declaration[] declarations;
		switch(trange.front.type) {
			case TokenType.OpenBrace :
				declarations = trange.parseAggregate();
				break;
			
			case TokenType.Colon :
				trange.popFront();
				declarations = trange.parseAggregate!false();
				break;
			
			default :
				declarations = [trange.parseDeclaration()];
				break;
		}
		
		location.spanTo(trange.front.location);
		return new StorageClassDeclaration(location, arguments, declarations);
	}
	
	switch(trange.front.type) {
		case TokenType.Auto :
			trange.popFront();
			
			return trange.parseTypedDeclaration(location, new AutoType(location));
		
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
					
					return handleStorageClass!ConstDeclaration();
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
					
					return handleStorageClass!ImmutableDeclaration();
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
					
					return handleStorageClass!InoutDeclaration();
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
					
					return handleStorageClass!SharedDeclaration();
				}
			}
			
			goto default;
		
		/*
		 * Storage class
		 */
		case TokenType.Abstract :
			trange.popFront();
			
			return handleStorageClass!AbstractDeclaration();
		
		case TokenType.Deprecated :
			trange.popFront();
			
			return handleStorageClass!DeprecatedDeclaration();
		
		case TokenType.Nothrow :
			trange.popFront();
			
			return handleStorageClass!NothrowDeclaration();
		
		case TokenType.Override :
			trange.popFront();
			
			return handleStorageClass!OverrideDeclaration();
		
		case TokenType.Pure :
			trange.popFront();
			
			return handleStorageClass!PureDeclaration();
		
		case TokenType.Static :
			// Handle static if.
			// TODO: handle static assert.
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == TokenType.If) {
				return trange.parseStaticIf!Declaration();
			}
			
			trange.popFront();
			return handleStorageClass!StaticDeclaration();
		
		case TokenType.Synchronized :
			trange.popFront();
			
			return handleStorageClass!SynchronizedDeclaration();
		
		case TokenType.__Gshared :
			trange.popFront();
			
			return handleStorageClass!__GsharedDeclaration();
		
		/*
		 * Visibility declaration
		 */
		case TokenType.Private :
			trange.popFront();
			
			return handleStorageClass!PrivateDeclaration();
		
		case TokenType.Public :
			trange.popFront();
			
			return handleStorageClass!PublicDeclaration();
		
		case TokenType.Protected :
			trange.popFront();
			
			return handleStorageClass!ProtectedDeclaration();
		
		case TokenType.Package :
			trange.popFront();
			
			return handleStorageClass!PackageDeclaration();
		
		case TokenType.Export :
			trange.popFront();
			
			return handleStorageClass!ExportDeclaration();
		
		/*
		 * Linkage
		 */
		case TokenType.Extern :
			trange.popFront();
			trange.match(TokenType.OpenParen);
			string linkage = trange.front.value;
			trange.match(TokenType.Identifier);
			trange.match(TokenType.CloseParen);
			
			return handleStorageClass!LinkageDeclaration(linkage);
		
		/**
		 * Attributes
		 */
		case TokenType.At :
			trange.popFront();
			string attribute = trange.front.value;
			trange.match(TokenType.Identifier);
			
			return handleStorageClass!AttributeDeclaration(attribute);
		
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
			
			Type type;
			
			// Determine if we are in case of manifest constant or regular enum.
			switch(lookahead.front.type) {
				case TokenType.Colon :
				case TokenType.OpenBrace :
					// FIXME: this is manifest constant !
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
			
			assert(type);
			return trange.parseTypedDeclaration(location, type);
		
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
		
		case TokenType.Mixin :
			return trange.parseMixin!Declaration();
		
		case TokenType.Unittest :
			trange.popFront();
			trange.parseBlock();
			assert(0, "unittest not supported");
		
		/*
		 * Variable and function declarations
		 */
		default :
			return trange.parseTypedDeclaration(location);
	}
	
	assert(0);
}

/**
 * Parse type identifier ... declarations.
 * Function/variables.
 */
Declaration parseTypedDeclaration(R)(ref R trange, Location location) if(isTokenRange!R) {
	return trange.parseTypedDeclaration(location, trange.parseType());
}

/**
 * Parse a declaration when you already have its type.
 */
Declaration parseTypedDeclaration(R)(ref R trange, Location location, Type type) if(isTokenRange!R) {
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
				
				value = trange.parseInitializer(type);
				
				variableLocation.spanTo(value.location);
			} else {
				value = new DefaultInitializer(type);
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
private Declaration parseAlias(R)(ref R trange) {
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
	
	auto parseModuleName(TokenRange)(ref TokenRange trange) {
		string[] mod = [trange.front.value];
		trange.match(TokenType.Identifier);
		while(trange.front.type == TokenType.Dot) {
			trange.popFront();
		
			mod ~= trange.front.value;
			trange.match(TokenType.Identifier);
		}
		
		return mod;
	}
	
	string[][] modules = [parseModuleName(trange)];
	while(trange.front.type == TokenType.Comma) {
		trange.popFront();
		
		modules ~= parseModuleName(trange);
	}
	
	location.spanTo(trange.front.location);
	trange.match(TokenType.Semicolon);
	
	return new ImportDeclaration(location, modules);
}

/**
 * Parse Initializer
 */
private auto parseInitializer(TokenRange)(ref TokenRange trange, Type type) {
	if(trange.front.type == TokenType.Void) {
		auto location = trange.front.location;
		
		trange.popFront();
		
		return new VoidInitializer(location, type);
	}
	
	return trange.parseAssignExpression();
}

