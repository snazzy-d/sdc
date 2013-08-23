module d.parser.dfunction;

import d.ast.dfunction;
import d.ast.declaration;
import d.ast.statement;
import d.ast.type;

import d.parser.base;
import d.parser.dtemplate;
import d.parser.expression;
import d.parser.statement;
import d.parser.type;
import d.parser.util;

/**
 * Parse constructor.
 */
Declaration parseConstructor(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto location = trange.front.location;
	trange.match(TokenType.This);
	
	assert(0, "Constructor not implemented");
	// return trange.parseFunction!(ConstructorDeclaration)(location);
}

/**
 * Parse destructor.
 */
Declaration parseDestructor(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto location = trange.front.location;
	trange.match(TokenType.Tilde);
	trange.match(TokenType.This);
	
	assert(0, "Destructor not implemented");
	// return trange.parseFunction!(DestructorDeclaration)(location);
}

/**
 * Parse function declaration, starting with parameters.
 * This allow to parse function as well as constructor or any special function.
 * Additionnal parameters are used to construct the function.
 */
Declaration parseFunction(FunctionDeclarationType = FunctionDeclaration, TokenRange, U... )(ref TokenRange trange, Location location, U arguments) if(isTokenRange!TokenRange) {
	// Function declaration.
	bool isVariadic;
	AstTemplateParameter[] tplParameters;
	
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
	FunctionAttributeLoop : while(1) {
		switch(trange.front.type) with(TokenType) {
			case Pure, Const, Immutable, Inout, Shared, Nothrow :
				trange.popFront();
				break;
			
			case At :
				// FIXME: Do something with attributes.
				trange.popFront();
				trange.match(Identifier);
				break;
			
			default :
				break FunctionAttributeLoop;
		}
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
	
	auto fun = new FunctionDeclarationType(location, arguments, parameters, isVariadic, fbody);
	
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
	
	ParamDecl[] parameters;
	
	switch(trange.front.type) with(TokenType) {
		case CloseParen :
			break;
		
		case TripleDot :
			trange.popFront();
			isVariadic = true;
			break;
		
		default :
			parameters ~= trange.parseParameter();
			
			while(trange.front.type == Comma) {
				trange.popFront();
				
				if(trange.front.type == TripleDot) {
					goto case TripleDot;
				}
				
				parameters ~= trange.parseParameter();
			}
	}
	
	trange.match(TokenType.CloseParen);
	
	return parameters;
}

private auto parseParameter(TokenRange)(ref TokenRange trange) {
	bool isRef;
	
	// TODO: parse storage class
	ParseStorageClassLoop: while(1) {
		switch(trange.front.type) with(TokenType) {
			case In, Out, Lazy :
				assert(0, "Not implemented");
			
			case Ref :
				trange.popFront();
				isRef = true;
				
				break;
			
			default :
				break ParseStorageClassLoop;
		}
	}
	
	auto location = trange.front.location;
	auto type = ParamAstType(trange.parseType(), isRef);
	
	if(trange.front.type == TokenType.Identifier) {
		string name = trange.front.value;
		trange.popFront();
		
		if(trange.front.type == TokenType.Assign) {
			trange.popFront();
			
			auto expr = trange.parseAssignExpression();
			
			location.spanTo(expr.location);
			return ParamDecl(location, type, name, expr);
		}
		
		return ParamDecl(location, type, name);
	} else {
		location.spanTo(trange.front.location);
		return ParamDecl(location, type);
	}
}

