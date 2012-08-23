module d.parser.dfunction;

import d.ast.dfunction;

import d.parser.base;
import d.parser.dtemplate;
import d.parser.expression;
import d.parser.statement;
import d.parser.type;
import d.parser.util;

import d.ast.declaration;
import d.ast.dtemplate;

/**
 * Parse constructor.
 */
auto parseConstructor(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto location = trange.front.location;
	trange.match(TokenType.This);
	
	return trange.parseFunction!(ConstructorDeclaration, ConstructorDefinition)(location);
}

/**
 * Parse destructor.
 */
auto parseDestructor(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto location = trange.front.location;
	trange.match(TokenType.Tilde);
	trange.match(TokenType.This);
	
	return trange.parseFunction!(DestructorDeclaration, DestructorDefinition)(location);
}

/**
 * Parse function declaration, starting with parameters.
 * This allow to parse function as well as constructor or any special function.
 * Additionnal parameters are used to construct the function.
 */
Declaration parseFunction(FunctionDeclarationType = FunctionDeclaration, FunctionDefinitionType = FunctionDefinition, TokenRange, U... )(ref TokenRange trange, Location location, U arguments) if(isTokenRange!TokenRange) {
	// Function declaration.
	bool isVariadic;
	TemplateParameter[] tplParameters;
	
	// Check if we have a function template
	auto lookahead = trange.save;
	lookahead.popMatchingDelimiter!(TokenType.OpenParen)();
	if(lookahead.front.type == TokenType.OpenParen) {
		tplParameters = trange.parseTemplateParameters();
	}
	
	auto parameters = trange.parseParameters(isVariadic);
	
	// If it is a template, it can have a constraint.
	if(tplParameters.ptr) {
		if(trange.front.type == TokenType.If) {
			trange.parseConstraint();
		}
	}
	
	// TODO: parse function attributes
	// Parse function attributes
	functionAttributeLoop : while(1) {
		switch(trange.front.type) {
			case TokenType.Pure, TokenType.Const, TokenType.Immutable, TokenType.Mutable, TokenType.Inout, TokenType.Shared, TokenType.Nothrow :
				trange.popFront();
				break;
			
			case TokenType.At :
				trange.popFront();
				trange.match(TokenType.Identifier);
				break;
			
			default :
				break functionAttributeLoop;
		}
	}
	
	// TODO: parse contracts.
	// Skip contracts
	switch(trange.front.type) {
		case TokenType.In, TokenType.Out :
			trange.popFront();
			trange.parseBlock();
			
			switch(trange.front.type) {
				case TokenType.In, TokenType.Out :
					trange.popFront();
					trange.parseBlock();
					break;
				
				default :
					break;
			}
			
			trange.match(TokenType.Body);
			break;
		
		case TokenType.Body :
			// Body without contract is just skipped.
			trange.popFront();
			break;
		
		default :
			break;
	}
	
	FunctionDeclarationType fun;
	
	switch(trange.front.type) {
		case TokenType.Semicolon :
			location.spanTo(trange.front.location);
			trange.popFront();
			
			fun = new FunctionDeclarationType(location, arguments, parameters);
			break;
		
		case TokenType.OpenBrace :
			auto fbody = trange.parseBlock();
			
			location.spanTo(trange.front.location);
			
			fun = new FunctionDefinitionType(location, arguments, parameters, fbody);
			break;
		
		default :
			// TODO: error.
			trange.match(TokenType.Begin);
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
auto parseParameters(TokenRange)(ref TokenRange trange, out bool isVariadic) {
	trange.match(TokenType.OpenParen);
	
	Parameter[] parameters;
	
	switch(trange.front.type) {
		case TokenType.CloseParen :
			break;
		
		case TokenType.TripleDot :
			trange.popFront();
			isVariadic = true;
			break;
		
		default :
			parameters ~= trange.parseParameter();
			
			while(trange.front.type == TokenType.Comma) {
				trange.popFront();
				
				if(trange.front.type == TokenType.TripleDot) {
					goto case TokenType.TripleDot;
				}
				
				parameters ~= trange.parseParameter();
			}
	}
	
	trange.match(TokenType.CloseParen);
	
	return parameters;
}

private auto parseParameter(TokenRange)(ref TokenRange trange) {
	// TODO: parse storage class
	ParseStorageClassLoop: while(1) {
		switch(trange.front.type) {
			case TokenType.In, TokenType.Out, TokenType.Lazy :
				trange.popFront();
				break;
			
			default :
				break ParseStorageClassLoop;
		}
	}
	
	auto type = trange.parseType();
	
	if(trange.front.type == TokenType.Identifier) {
		auto location = type.location;
		
		string name = trange.front.value;
		trange.popFront();
		
		if(trange.front.type == TokenType.Assign) {
			trange.popFront();
			
			auto expression = trange.parseAssignExpression();
			
			location.spanTo(expression.location);
			return new InitializedParameter(location, type, name, expression);
		}
		
		return new Parameter(location, type, name);
	}
	
	return new Parameter(type.location, type);
}

