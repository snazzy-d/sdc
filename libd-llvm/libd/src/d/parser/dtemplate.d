module d.parser.dtemplate;

import d.ast.base;
import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.parser.base;
import d.parser.declaration;
import d.parser.expression;
import d.parser.type;

import std.range;

auto parseTemplate(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	Location location = trange.front.location;
	trange.match(TokenType.Template);
	
	string name = trange.front.value;
	trange.match(TokenType.Identifier);
	
	auto parameters = trange.parseTemplateParameters();
	auto declarations = trange.parseAggregate();
	
	location.spanTo(declarations.back.location);
	
	return new TemplateDeclaration(location, name, parameters, declarations);
}

auto parseConstraint(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	trange.match(TokenType.If);
	trange.match(TokenType.OpenParen);
	
	trange.parseExpression();
	
	trange.match(TokenType.CloseParen);
}

auto parseTemplateParameters(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	trange.match(TokenType.OpenParen);
	
	TemplateParameter[] parameters;
	
	if(trange.front.type != TokenType.CloseParen) {
		parameters ~= trange.parseTemplateParameter();
		
		while(trange.front.type != TokenType.CloseParen) {
			trange.match(TokenType.Comma);
			
			parameters ~= trange.parseTemplateParameter();
		}
	}
	
	trange.match(TokenType.CloseParen);
	
	return parameters;
}

private TemplateParameter parseTemplateParameter(TokenRange)(ref TokenRange trange) {
	switch(trange.front.type) {
		case TokenType.Identifier :
			auto lookahead = trange.save;
			lookahead.popFront();
			switch(lookahead.front.type) {
				// Identifier followed by ":", "=", "," or ")" are type parameters.
				case TokenType.Colon, TokenType.Assign, TokenType.Comma, TokenType.CloseParen :
					return trange.parseTypeParameter();
				
				case TokenType.TripleDot :
					string name = trange.front.value;
					auto location = lookahead.front.location;
					
					trange.popFrontN(2);
					return new TupleTemplateParameter(location, name);
				
				default :
					// We probably have a value parameter (or an error).
					assert(0, "Value parameter is not implemented");
					// return trange.parseValueParameter();
			}
		
		case TokenType.Alias :
			assert(0, "Alias parameter is not implemented");
			// return trange.parseAliasParameter();
		
		case TokenType.This :
			Location location = trange.front.location;
			trange.popFront();
			
			string name = trange.front.value;
			location.spanTo(trange.front.location);
			
			trange.match(TokenType.Identifier);
			
			return new ThisTemplateParameter(location, name);
		
		default :
			// We probably have a value parameter (or an error).
			// return trange.parseValueParameter();
			assert(0);
	}
}

private auto parseTypeParameter(TokenRange)(ref TokenRange trange) {
	string name = trange.front.value;
	Location location = trange.front.location;
	
	trange.match(TokenType.Identifier);
	
	switch(trange.front.type) {
		// TODO: handle default parameter and specialisation.
		case TokenType.Colon :
			trange.popFront();
			trange.parseType();
			
			if(trange.front.type == TokenType.Assign) goto case TokenType.Assign;
			
			goto default;
		
		case TokenType.Assign :
			trange.popFront();
			trange.parseType();
			
			goto default;
		
		default :
			return new TypeTemplateParameter(location, name);
	}
}
/+
private auto parseValueParameter(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	auto type = trange.parseType();
	string name = trange.front.value;
	
	location.spanTo(trange.front.location);
	trange.match(TokenType.Identifier);
	
	if(trange.front.type == TokenType.Assign) {
		trange.popFront();
		switch(trange.front.type) {
			case TokenType.__File__, TokenType.__Line__ :
				location.spanTo(trange.front.location);
				
				trange.popFront();
				break;
			
			default :
				auto expression = trange.parseAssignExpression();
				location.spanTo(expression.location);
		}
	}
	
	return new ValueTemplateParameter(location, name, type);
}

private TemplateParameter parseAliasParameter(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	trange.match(TokenType.Alias);
	
	bool isTyped = false;
	if(trange.front.type != TokenType.Identifier) {
		isTyped = true;
	} else {
		// Identifier followed by ":", "=", "," or ")" are untyped alias parameters.
		auto lookahead = trange.save;
		lookahead.popFront();
		auto nextType = lookahead.front.type;
		if(nextType != TokenType.Colon && nextType != TokenType.Assign && nextType != TokenType.Comma && nextType != TokenType.CloseParen) {
			isTyped = true;
		}
	}
	
	if(isTyped) {
		auto type = trange.parseType();
		string name = trange.front.value;
		
		location.spanTo(trange.front.location);
		
		trange.match(TokenType.Identifier);
		
		return new TypedAliasTemplateParameter(location, name, type);
	} else {
		string name = trange.front.value;
		location.spanTo(trange.front.location);
		
		trange.match(TokenType.Identifier);
		
		return new AliasTemplateParameter(location, name);
	}
}
+/
auto parseTemplateArguments(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	TemplateArgument[] arguments;
	
	switch(trange.front.type) with(TokenType) {
		case OpenParen :
			trange.popFront();
			
			if(trange.front.type != CloseParen) {
				arguments ~= trange.parseTemplateArgument();
		
				while(trange.front.type != CloseParen) {
					trange.match(Comma);
					arguments ~= trange.parseTemplateArgument();
				}
			}
			
			trange.match(CloseParen);
			break;
		
		case Identifier :
			auto identifier = new BasicIdentifier(trange.front.location, trange.front.value);
			arguments ~= new IdentifierTemplateArgument(identifier);
			
			trange.popFront();
			break;
		/+
		case TokenType.True, TokenType.False, TokenType.Null, TokenType.IntegerLiteral, TokenType.StringLiteral, TokenType.CharacterLiteral, TokenType.__File__, TokenType.__Line__, TokenType.Is :
			arguments = [new ValueTemplateArgument(trange.parsePrimaryExpression())];
			break;
		+/
		default :
			auto location = trange.front.location;
			auto type = trange.parseBasicType();
			
			location.spanTo(trange.front.location);
			arguments ~= new TypeTemplateArgument(location, type);
			break;
	}
	
	return arguments;
}

auto parseTemplateArgument(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto location = trange.front.location;
	
	import d.parser.ambiguous;
	return trange.parseAmbiguous!(delegate TemplateArgument(parsed) {
		import std.stdio;
		
		static if(is(typeof(parsed) : QualAstType)) {
			location.spanTo(trange.front.location);
			return new TypeTemplateArgument(location, parsed);
		} else static if(is(typeof(parsed) : AstExpression)) {
			writeln(typeid(parsed));
			return new ValueTemplateArgument(parsed);
		} else {
			writeln(typeid(parsed));
			return new IdentifierTemplateArgument(parsed);
		}
	})();
}

