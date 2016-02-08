module d.parser.declaration;

import d.parser.adt;
import d.parser.base;
import d.parser.conditional;
import d.parser.expression;
import d.parser.identifier;
import d.parser.statement;
import d.parser.dtemplate;
import d.parser.type;

import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.ir.expression;

import d.context.name;

/**
 * Parse a set of declarations.
 */
auto parseAggregate(bool globBraces = true)(ref TokenRange trange) {
	static if (globBraces) {
		trange.match(TokenType.OpenBrace);
	}
	
	Declaration[] declarations;
	
	while(!trange.empty && trange.front.type != TokenType.CloseBrace) {
		declarations ~= trange.parseDeclaration();
	}
	
	static if (globBraces) {
		trange.match(TokenType.CloseBrace);
	}
	
	return declarations;
}

/**
 * Parse a declaration
 */
Declaration parseDeclaration(ref TokenRange trange) {
	auto location = trange.front.location;
	
	// First, declarations that do not support storage classes.
	switch(trange.front.type) with(TokenType) {
		case Static :
			// Handle static if.
			auto lookahead = trange.save;
			lookahead.popFront();
			switch(lookahead.front.type) {
				case If:
					return trange.parseStaticIf!Declaration();
				
				case Assert:
					return trange.parseStaticAssert!Declaration();
				
				default:
					break;
			}
			
			break;
		
		case Import :
			return trange.parseImport();
		
		case Version :
			return trange.parseVersion!Declaration();
		
		case Debug :
			return trange.parseDebug!Declaration();
		
		case Mixin :
			return trange.parseMixin!Declaration();
		
		default :
			break;
	}
	
	auto qualifier = TypeQualifier.Mutable;
	StorageClass stc = defaultStorageClass;

	StorageClassLoop: while(true) {
		switch(trange.front.type) with(TokenType) {
			case Const :
				qualifier = TypeQualifier.Const;
				goto HandleTypeQualifier;
			
			case Immutable :
				qualifier = TypeQualifier.Immutable;
				goto HandleTypeQualifier;
			
			case Inout :
				qualifier = TypeQualifier.Inout;
				goto HandleTypeQualifier;
			
			case Shared :
				qualifier = TypeQualifier.Shared;
				goto HandleTypeQualifier;
			
			HandleTypeQualifier: {
				auto lookahead = trange.save;
				lookahead.popFront();
				if (lookahead.front.type == OpenParen) {
					// This is a type not a storage class.
					break StorageClassLoop;
				}
				
				// We have a qualifier(type) name type of declaration.
				stc.hasQualifier = true;
				stc.qualifier = stc.qualifier.add(qualifier);
				goto HandleStorageClass;
			}
			
			case Ref :
				stc.isRef = true;
				goto HandleStorageClass;
			
			case Abstract :
				stc.isAbstract = true;
				goto HandleStorageClass;
			
			case Deprecated :
				stc.isDeprecated = true;
				goto HandleStorageClass;
			
			case Nothrow :
				stc.isNoThrow = true;
				goto HandleStorageClass;
			
			case Override :
				stc.isOverride = true;
				goto HandleStorageClass;
			
			case Pure :
				stc.isPure = true;
				goto HandleStorageClass;
			
			case Static :
				stc.isStatic = true;
				goto HandleStorageClass;
			
			case Synchronized :
				stc.isSynchronized = true;
				goto HandleStorageClass;
			
			case __Gshared :
				stc.isGshared = true;
				goto HandleStorageClass;
			
			case Private :
				stc.hasVisibility = true;
				stc.visibility = Visibility.Private;
				goto HandleStorageClass;
			
			case Package :
				stc.hasVisibility = true;
				stc.visibility = Visibility.Package;
				goto HandleStorageClass;
			
			case Protected :
				stc.hasVisibility = true;
				stc.visibility = Visibility.Protected;
				goto HandleStorageClass;
			
			case Public :
				stc.hasVisibility = true;
				stc.visibility = Visibility.Public;
				goto HandleStorageClass;
			
			case Export :
				stc.hasVisibility = true;
				stc.visibility = Visibility.Export;
				goto HandleStorageClass;
			
			HandleStorageClass:
				trange.popFront();
				break;
			
			case Extern :
				trange.popFront();
				trange.match(OpenParen);
				auto linkageName = trange.front.name;
				trange.match(Identifier);
				
				stc.hasLinkage = true;
				if (linkageName == BuiltinName!"D") {
					stc.linkage = Linkage.D;
				} else if (linkageName == BuiltinName!"C") {
					// TODO: C++
					stc.linkage = Linkage.C;
				} else if (linkageName == BuiltinName!"Windows") {
					stc.linkage = Linkage.Windows;
				} else if (linkageName == BuiltinName!"System") {
					stc.linkage = Linkage.System;
				} else if (linkageName == BuiltinName!"Pascal") {
					stc.linkage = Linkage.Pascal;
				} else if (linkageName == BuiltinName!"Java") {
					stc.linkage = Linkage.Java;
				} else {
					assert(0, "Linkage not supported : " ~ linkageName.toString(trange.context));
				}
				
				trange.match(CloseParen);
				break;
			
			// Enum is a bit of a strange beast. half storage class, half declaration itself.
			case Enum :
				stc.isEnum = true;
				
				auto lookahead = trange.save;
				lookahead.popFront();
				
				switch(lookahead.front.type) {
					// enum : and enum { are special construct,
					// not classic storage class declaration.
					case Colon, OpenBrace :
						return trange.parseEnum(stc);
					
					case Identifier :
						lookahead.popFront();
						switch(lookahead.front.type) {
							// Named verion of the above.
							case Colon, OpenBrace :
								return trange.parseEnum(stc);
							
							default:
								break;
						}
						
						break;
					
					default :
						break;
				}
				
				goto HandleStorageClass;
			
			case At :
				trange.popFront();
				auto attr = trange.front.name;
				trange.match(Identifier);
				
				if (attr == BuiltinName!"property") {
					stc.isProperty = true;
				} else if (attr == BuiltinName!"nogc") {
					stc.isNoGC = true;
				} else {
					assert(0, "@" ~ attr.toString(trange.context) ~ " is not supported.");
				}
				
				break;
			
			default:
				break StorageClassLoop;
		}
		
		switch(trange.front.type) with(TokenType) {
			case Identifier:
				auto lookahead = trange.save;
				lookahead.popFront();
				if (lookahead.front.type == Equal) {
					return trange.parseTypedDeclaration(location, stc, AstType.getAuto());
				}
				
				break StorageClassLoop;
			
			case Colon :
				trange.popFront();
				auto declarations = trange.parseAggregate!false();
				
				location.spanTo(trange.front.location);
				return new GroupDeclaration(location, stc, declarations);
			
			case OpenBrace :
				auto declarations = trange.parseAggregate();
				
				location.spanTo(trange.front.location);
				return new GroupDeclaration(location, stc, declarations);
			
			default :
				break;
		}
	}
	
	switch(trange.front.type) with(TokenType) {
		// XXX: auto as a storage class ?
		case Auto :
			trange.popFront();
			return trange.parseTypedDeclaration(location, stc, AstType.getAuto());
		
		case Interface :
			return trange.parseInterface(stc);
		
		case Class :
			return trange.parseClass(stc);
		
		case Struct :
			return trange.parseStruct(stc);
		
		case Union :
			return trange.parseUnion(stc);
		
		case This :
			return trange.parseConstructor(stc);
		
		case Tilde :
			return trange.parseDestructor(stc);
		
		case Template :
			return trange.parseTemplate(stc);
		
		case Alias :
			return trange.parseAlias(stc);
		
		case Unittest :
			trange.popFront();
			trange.parseBlock();
			assert(0, "unittest not supported");
		
		default :
			return trange.parseTypedDeclaration(location, stc);
	}
	
	assert(0);
}

/**
 * Parse type identifier ... declarations.
 * Function/variables.
 */
Declaration parseTypedDeclaration(ref TokenRange trange, Location location, StorageClass stc) {
	return trange.parseTypedDeclaration(location, stc, trange.parseType());
}

/**
 * Parse a declaration when you already have its type.
 */
Declaration parseTypedDeclaration(ref TokenRange trange, Location location, StorageClass stc, AstType type) {
	auto lookahead = trange.save;
	lookahead.popFront();
	if (lookahead.front.type == TokenType.OpenParen) {
		auto idLoc = trange.front.location;
		auto name = trange.front.name;
		trange.match(TokenType.Identifier);
		
		if (name.isReserved) {
			import d.exception;
			throw new CompileException(idLoc, name.toString(trange.context) ~ " is a reserved name");
		}
		
		// TODO: implement ref return.
		return trange.parseFunction(location, stc, type.getParamType(stc.isRef, false), name);
	} else {
		Declaration[] variables;
		
		while(true) {
			auto name = trange.front.name;
			Location variableLocation = trange.front.location;
			trange.match(TokenType.Identifier);
			
			AstExpression value;
			if (trange.front.type == TokenType.Equal) {
				trange.popFront();
				value = trange.parseInitializer();
				variableLocation.spanTo(value.location);
			}
			
			variables ~= new VariableDeclaration(location, stc, type, name, value);
			
			if (trange.front.type != TokenType.Comma) {
				break;
			}
			
			trange.popFront();
		}
		
		location.spanTo(trange.front.location);
		trange.match(TokenType.Semicolon);
		
		return new GroupDeclaration(location, stc, variables);
	}
}

// XXX: one callsite, remove
private Declaration parseConstructor(ref TokenRange trange, StorageClass stc) {
	auto location = trange.front.location;
	trange.match(TokenType.This);
	
	return trange.parseFunction(location, stc, AstType.getAuto().getParamType(false, false), BuiltinName!"__ctor");
}

// XXX: one callsite, remove
private Declaration parseDestructor(ref TokenRange trange, StorageClass stc) {
	auto location = trange.front.location;
	trange.match(TokenType.Tilde);
	trange.match(TokenType.This);
	
	return trange.parseFunction(location, stc, AstType.getAuto().getParamType(false, false), BuiltinName!"__dtor");
}

/**
 * Parse function declaration, starting with parameters.
 * This allow to parse function as well as constructor or any special function.
 * Additionnal parameters are used to construct the function.
 */
private Declaration parseFunction(ref TokenRange trange, Location location, StorageClass stc, ParamAstType returnType, Name name) {
	// Function declaration.
	bool isVariadic;
	AstTemplateParameter[] tplParameters;
	AstExpression constraint;
	
	// Check if we have a function template
	import d.parser.util;
	auto lookahead = trange.save;
	lookahead.popMatchingDelimiter!(TokenType.OpenParen)();
	
	bool isTemplate = lookahead.front.type == TokenType.OpenParen;
	if (isTemplate) {
		tplParameters = trange.parseTemplateParameters();
	}
	
	auto parameters = trange.parseParameters(isVariadic);
	
	// If it is a template, it can have a constraint.
	if (isTemplate) {
		if (trange.front.type == TokenType.If) {
			constraint = trange.parseConstraint();
		}
	}
	
	auto qualifier = TypeQualifier.Mutable;
	
	while(1) {
		switch(trange.front.type) with(TokenType) {
			case Pure :
				stc.isPure = true;
				goto HandleStorageClass;
			
			case Const :
				qualifier = TypeQualifier.Const;
				goto HandleTypeQualifier;
			
			case Immutable :
				qualifier = TypeQualifier.Immutable;
				goto HandleTypeQualifier;
			
			case Inout :
				qualifier = TypeQualifier.Inout;
				goto HandleTypeQualifier;
			
			case Shared :
				qualifier = TypeQualifier.Shared;
				goto HandleTypeQualifier;
			
			HandleTypeQualifier: {
				// We have a qualifier(type) name type of declaration.
				stc.hasQualifier = true;
				stc.qualifier = stc.qualifier.add(qualifier);
				goto HandleStorageClass;
			}
			
			HandleStorageClass:
				trange.popFront();
				break;
			
			case At :
				trange.popFront();
				auto attr = trange.front.name;
				trange.match(Identifier);
				
				if (attr == BuiltinName!"property") {
					stc.isProperty = true;
				} else if (attr == BuiltinName!"nogc") {
					stc.isNoGC = true;
				} else {
					assert(0, "@" ~ attr.toString(trange.context) ~ " is not supported.");
				}
				
				continue;
			
			default :
				break;
		}
		
		break;
	}
	
	// TODO: parse contracts.
	// Skip contracts
	switch(trange.front.type) with(TokenType) {
		case In, Out :
			trange.popFront();
			trange.parseBlock();
			
			switch(trange.front.type) {
				case In, Out :
					trange.popFront();
					trange.parseBlock();
					break;
				
				default :
					break;
			}
			
			trange.match(Body);
			break;
		
		case Body :
			// Body without contract is just skipped.
			trange.popFront();
			break;
		
		default :
			break;
	}
	
	import d.ast.statement;
	AstBlockStatement fbody;
	switch(trange.front.type) with(TokenType) {
		case Semicolon :
			location.spanTo(trange.front.location);
			trange.popFront();
			
			break;
		
		case OpenBrace :
			fbody = trange.parseBlock();
			location.spanTo(fbody.location);
			
			break;
		
		default :
			// TODO: error.
			trange.match(Begin);
			assert(0);
	}
	
	auto fun = new FunctionDeclaration(location, stc, returnType, name, parameters, isVariadic, fbody);
	return isTemplate
		? new TemplateDeclaration(location, stc, fun.name, tplParameters, [fun], constraint)
		: fun;
}

/**
 * Parse function and delegate parameters.
 */
auto parseParameters(ref TokenRange trange, out bool isVariadic) {
	trange.match(TokenType.OpenParen);
	
	ParamDecl[] parameters;
	
	switch(trange.front.type) with(TokenType) {
		case CloseParen :
			break;
		
		case DotDotDot :
			trange.popFront();
			isVariadic = true;
			break;
		
		default :
			parameters ~= trange.parseParameter();
			
			while(trange.front.type == Comma) {
				trange.popFront();
				
				if (trange.front.type == DotDotDot) {
					goto case DotDotDot;
				}
				
				if (trange.front.type == CloseParen) {
					goto case CloseParen;
				}
				
				parameters ~= trange.parseParameter();
			}
	}
	
	trange.match(TokenType.CloseParen);
	
	return parameters;
}

/**
 * Parse Initializer
 */
auto parseInitializer(ref TokenRange trange) {
	if (trange.front.type != TokenType.Void) {
		return trange.parseAssignExpression();
	}
	
	auto location = trange.front.location;
	
	trange.popFront();
	return new AstVoidInitializer(location);
}

private:
auto parseParameter(ref TokenRange trange) {
	bool isRef;
	
	// TODO: parse storage class
	ParseStorageClassLoop: while(1) {
		switch(trange.front.type) with(TokenType) {
			case In, Out, Lazy :
				assert(0, "storageclasses: in, out and lazy  are not yet implemented");
			
			case Ref :
				trange.popFront();
				isRef = true;
				
				break;
			
			default :
				break ParseStorageClassLoop;
		}
	}
	
	auto location = trange.front.location;
	auto type = trange.parseType().getParamType(isRef, false);
	
	auto name = BuiltinName!"";
	AstExpression value;
	
	if (trange.front.type == TokenType.Identifier) {
		name = trange.front.name;
		
		trange.popFront();
		if (trange.front.type == TokenType.Equal) {
			trange.popFront();
			value = trange.parseAssignExpression();
		}
	}
	
	location.spanTo(trange.front.location);
	return ParamDecl(location, type, name, value);
}

/**
 * Parse alias declaration
 */
Declaration parseAlias(ref TokenRange trange, StorageClass stc) {
	Location location = trange.front.location;
	trange.match(TokenType.Alias);
	
	auto name = trange.front.name;
	trange.match(TokenType.Identifier);
	
	if (trange.front.type == TokenType.Equal) {
		trange.popFront();
		
		import d.parser.ambiguous;
		return trange.parseAmbiguous!(delegate Declaration(parsed) {
			location.spanTo(trange.front.location);
			trange.match(TokenType.Semicolon);
			
			alias T = typeof(parsed);
			static if (is(T : AstType)) {
				return new TypeAliasDeclaration(location, stc, name, parsed);
			} else static if (is(T : AstExpression)) {
				return new ValueAliasDeclaration(location, stc, name, parsed);
			} else {
				return new IdentifierAliasDeclaration(location, stc, name, parsed);
			}
		})();
	} else if (trange.front.type == TokenType.This) {
		// FIXME: move this before storage class parsing.
		trange.popFront();
		location.spanTo(trange.front.location);
		trange.match(TokenType.Semicolon);
		
		return new AliasThisDeclaration(location, name);
	}
	
	trange.match(TokenType.Begin);
	assert(0);
}

/**
 * Parse import declaration
 */
auto parseImport(ref TokenRange trange) {
	Location location = trange.front.location;
	trange.match(TokenType.Import);
	
	auto parseModuleName(TokenRange)(ref TokenRange trange) {
		auto mod = [trange.front.name];
		trange.match(TokenType.Identifier);
		while(trange.front.type == TokenType.Dot) {
			trange.popFront();
		
			mod ~= trange.front.name;
			trange.match(TokenType.Identifier);
		}
		
		return mod;
	}
	
	auto modules = [parseModuleName(trange)];
	while(trange.front.type == TokenType.Comma) {
		trange.popFront();
		
		modules ~= parseModuleName(trange);
	}
	
	location.spanTo(trange.front.location);
	trange.match(TokenType.Semicolon);
	
	return new ImportDeclaration(location, modules);
}
