module d.parser.declaration;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.ir.expression;

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
		switch(trange.front.type) with(TokenType) {
			case OpenBrace :
				declarations = trange.parseAggregate();
				break;
			
			case Colon :
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
	
	switch(trange.front.type) with(TokenType) {
		case Auto :
			trange.popFront();
			
			return trange.parseTypedDeclaration(location, QualAstType(new AutoType()));
		
		/*
		 * Type qualifiers
		 */
		case Const :
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == Identifier) {
				lookahead.popFront();
				if(lookahead.front.type == Assign) {
					trange.popFront();
					
					return handleStorageClass!ConstDeclaration();
				}
			}
			
			goto default;
		
		case Immutable :
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == Identifier) {
				lookahead.popFront();
				if(lookahead.front.type == Assign) {
					trange.popFront();
					
					return handleStorageClass!ImmutableDeclaration();
				}
			}
			
			goto default;
		
		case Inout :
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == Identifier) {
				lookahead.popFront();
				if(lookahead.front.type == Assign) {
					trange.popFront();
					
					return handleStorageClass!InoutDeclaration();
				}
			}
			
			goto default;
		
		case Shared :
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == Identifier) {
				lookahead.popFront();
				if(lookahead.front.type == Assign) {
					trange.popFront();
					
					return handleStorageClass!SharedDeclaration();
				}
			}
			
			goto default;
		
		/*
		 * Storage class
		 */
		case Abstract :
			trange.popFront();
			
			return handleStorageClass!AbstractDeclaration();
		
		case Deprecated :
			trange.popFront();
			
			return handleStorageClass!DeprecatedDeclaration();
		
		case Nothrow :
			trange.popFront();
			
			return handleStorageClass!NothrowDeclaration();
		
		case Override :
			trange.popFront();
			
			return handleStorageClass!OverrideDeclaration();
		
		case Pure :
			trange.popFront();
			
			return handleStorageClass!PureDeclaration();
		
		case Static :
			// Handle static if.
			// TODO: handle static assert.
			auto lookahead = trange.save;
			lookahead.popFront();
			if(lookahead.front.type == If) {
				return trange.parseStaticIf!Declaration();
			}
			
			trange.popFront();
			return handleStorageClass!StaticDeclaration();
		
		case Synchronized :
			trange.popFront();
			
			return handleStorageClass!SynchronizedDeclaration();
		
		case __Gshared :
			trange.popFront();
			
			return handleStorageClass!__GsharedDeclaration();
		
		/*
		 * Visibility declaration
		 */
		case Private :
			trange.popFront();
			
			return handleStorageClass!PrivateDeclaration();
		
		case Public :
			trange.popFront();
			
			return handleStorageClass!PublicDeclaration();
		
		case Protected :
			trange.popFront();
			
			return handleStorageClass!ProtectedDeclaration();
		
		case Package :
			trange.popFront();
			
			return handleStorageClass!PackageDeclaration();
		
		case Export :
			trange.popFront();
			
			return handleStorageClass!ExportDeclaration();
		
		/*
		 * Linkage
		 */
		case Extern :
			trange.popFront();
			trange.match(OpenParen);
			string linkageStr = trange.front.value;
			trange.match(Identifier);
			
			Linkage linkage;
			switch(linkageStr) {
				case "D" :
					linkage = Linkage.D;
					break;
				
				case "C" :
					// TODO: C++
					linkage = Linkage.C;
					break;
				
				default:
					assert(0, "Linkage not supported");
			}		
					
			trange.match(CloseParen);
			
			return handleStorageClass!LinkageDeclaration(linkage);
		
		/**
		 * Attributes
		 */
		case At :
			trange.popFront();
			string attribute = trange.front.value;
			trange.match(Identifier);
			
			return handleStorageClass!AttributeDeclaration(attribute);
		
		/*
		 * Class, interface, struct and union declaration
		 */
		case Interface :
			return trange.parseInterface();
		
		case Class :
			return trange.parseClass();
		
		case Struct :
			return trange.parseStruct();
		
		case Union :
			return trange.parseUnion();
		
		/*
		 * Constructor and destructor
		 */
		case This :
			return trange.parseConstructor();
		
		case Tilde :
			return trange.parseDestructor();
		
		/*
		 * Enum
		 */
		case Enum :
			auto lookahead = trange.save;
			lookahead.popFront();
			
			QualAstType type;
			
			// Determine if we are in case of manifest constant or regular enum.
			switch(lookahead.front.type) {
				case Colon :
				case OpenBrace :
					// FIXME: this is manifest constant !
					return trange.parseEnum();
				
				case Identifier :
					lookahead.popFront();
					switch(lookahead.front.type) {
						case Colon, OpenBrace :
							return trange.parseEnum();
						
						// Auto manifest constant declaration.
						case Assign :
							trange.popFront();
							type = QualAstType(new AutoType());
							
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
			
			assert(type.type);
			return trange.parseTypedDeclaration(location, type);
		
		/*
		 * Template
		 */
		case Template :
			assert(0, "Template not implemented");
			// return trange.parseTemplate();
		
		/*
		 * Import
		 */
		case Import :
			return trange.parseImport();
		
		/**
		 * Alias
		 */
		case Alias :
			return trange.parseAlias();
		
		/*
		 * Conditional compilation
		 */
		case Version :
			return trange.parseVersion!Declaration();
		
		case Debug :
			return trange.parseDebug!Declaration();
		
		case Mixin :
			return trange.parseMixin!Declaration();
		
		case Unittest :
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
Declaration parseTypedDeclaration(R)(ref R trange, Location location, QualAstType type) if(isTokenRange!R) {
	auto lookahead = trange.save;
	lookahead.popFront();
	if(lookahead.front.type == TokenType.OpenParen) {
		string name = trange.front.value;
		trange.match(TokenType.Identifier);
		
		return trange.parseFunction(location, Linkage.D, ParamAstType(type), name);
	} else {
		VariableDeclaration[] variables;
		
		// Variables declaration.
		void parseVariableDeclaration() {
			string name = trange.front.value;
			Location variableLocation = trange.front.location;
			trange.match(TokenType.Identifier);
			
			AstExpression value;
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
private auto parseInitializer(TokenRange)(ref TokenRange trange) {
	if(trange.front.type == TokenType.Void) {
		auto location = trange.front.location;
		
		trange.popFront();
		
		return new VoidInitializer(location);
	}
	
	return trange.parseAssignExpression();
}

