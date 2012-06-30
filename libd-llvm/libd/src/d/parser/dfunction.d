module d.parser.dfunction;

import d.ast.dfunction;

import d.parser.dtemplate;
import d.parser.expression;
import d.parser.statement;
import d.parser.type;
import d.parser.util;

import d.ast.declaration;
import d.ast.dtemplate;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

/**
 * Parse constructor.
 */
auto parseConstructor(TokenStream tstream) {
	auto location = match(tstream, TokenType.This).location;
	
	return parseFunction!(ConstructorDeclaration, ConstructorDefinition)(tstream, location);
}

/**
 * Parse destructor.
 */
auto parseDestructor(TokenStream tstream) {
	auto location = match(tstream, TokenType.Tilde).location;
	match(tstream, TokenType.This);
	
	return parseFunction!(DestructorDeclaration, DestructorDefinition)(tstream, location);
}

/**
 * Parse function declaration, starting with parameters.
 * This allow to parse function as well as constructor or any special function.
 * Additionnal parameters are used to construct the function.
 */
Declaration parseFunction(FunctionDeclarationType = FunctionDeclaration, FunctionDefinitionType = FunctionDefinition, U... )(TokenStream tstream, Location location, U arguments) {
	// Function declaration.
	bool isVariadic;
	TemplateParameter[] tplParameters;
	
	// Check if we have a function template
	if(lookAfterMatchingDelimiter!(TokenType.OpenParen)(tstream).type == TokenType.OpenParen) {
		tplParameters = parseTemplateParameters(tstream);
	}
	
	auto parameters = parseParameters(tstream, isVariadic);
	
	// If it is a template, it can have a constraint.
	if(tplParameters.ptr) {
		if(tstream.peek.type == TokenType.If) {
			parseConstraint(tstream);
		}
	}
	
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
	
	FunctionDeclarationType fun;
	
	switch(tstream.peek.type) {
		case TokenType.Semicolon :
			location.spanTo(tstream.peek.location);
			tstream.get();
			
			fun = new FunctionDeclarationType(location, arguments, parameters);
			break;
		
		case TokenType.OpenBrace :
			auto fbody = parseBlock(tstream);
			
			location.spanTo(tstream.peek.location);
			
			fun = new FunctionDefinitionType(location, arguments, parameters, fbody);
			break;
		
		default :
			// TODO: error.
			match(tstream, TokenType.Begin);
			assert(0);
	}
	
	if(tplParameters.ptr) {
		return new TemplateDeclaration(location, fun.name, tplParameters, [fun]);
	} else {
		return fun;
	}
}

/**
 * Parse function and delegate parameters.
 */
auto parseParameters(TokenStream tstream, out bool isVariadic) {
	match(tstream, TokenType.OpenParen);
	
	Parameter[] parameters;
	
	if(tstream.peek.type != TokenType.CloseParen) {
		parameters ~= parseParameter(tstream);
		
		while(tstream.peek.type == TokenType.Comma) {
			tstream.get();
			
			if(tstream.peek.type == TokenType.TripleDot) {
				tstream.get();
				isVariadic = true;
				break;
			}
			
			parameters ~= parseParameter(tstream);
		}
	}
	
	match(tstream, TokenType.CloseParen);
	
	return parameters;
}

auto parseParameter(TokenStream tstream) {
	// TODO: parse storage class
	bool parseStorageClass = true;
	while(parseStorageClass) {
		switch(tstream.peek.type) {
			case TokenType.In, TokenType.Out, TokenType.Lazy :
				tstream.get();
				break;
			
			default :
				parseStorageClass = false;
				break;
		}
	}
	
	auto type = parseType(tstream);
	
	if(tstream.peek.type == TokenType.Identifier) {
		auto location = type.location;
		
		string name = tstream.get().value;
		
		if(tstream.peek.type == TokenType.Assign) {
			tstream.get();
			
			auto expression = parseAssignExpression(tstream);
			
			location.spanTo(tstream.previous.location);
			return new InitializedParameter(location, type, name, expression);
		}
		
		location.spanTo(tstream.previous.location);
		return new NamedParameter(location, type, name);
	}
	
	return new Parameter(type.location, type);
}

