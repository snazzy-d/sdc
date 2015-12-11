module d.parser.dtemplate;

import d.ast.declaration;
import d.ast.expression;
import d.ast.identifier;
import d.ast.type;

import d.parser.base;
import d.parser.declaration;
import d.parser.expression;
import d.parser.type;

auto parseTemplate(ref TokenRange trange, StorageClass stc) {
	auto location = trange.front.location;
	AstExpression constraint;
	trange.match(TokenType.Template);
	
	auto name = trange.front.name;
	trange.match(TokenType.Identifier);
	
	auto parameters = trange.parseTemplateParameters();
	if (trange.front.type == TokenType.If) {
		constraint = trange.parseConstraint();
	}
	auto declarations = trange.parseAggregate();
	
	location.spanTo(declarations[$ - 1].location);
	
	return new TemplateDeclaration(location, stc, name, parameters, declarations, constraint);
}

auto parseConstraint(ref TokenRange trange) {
	trange.match(TokenType.If);
	trange.match(TokenType.OpenParen);
	
	auto constraint = trange.parseExpression();
	
	trange.match(TokenType.CloseParen);

	return constraint;
}

auto parseTemplateParameters(ref TokenRange trange) {
	trange.match(TokenType.OpenParen);
	
	AstTemplateParameter[] parameters;
	
	if (trange.front.type != TokenType.CloseParen) {
		parameters ~= trange.parseTemplateParameter();
		
		while(trange.front.type != TokenType.CloseParen) {
			trange.match(TokenType.Comma);
			
			parameters ~= trange.parseTemplateParameter();
		}
	}
	
	trange.match(TokenType.CloseParen);
	
	return parameters;
}

private AstTemplateParameter parseTemplateParameter(ref TokenRange trange) {
	switch(trange.front.type) with(TokenType) {
		case Identifier :
			auto lookahead = trange.save;
			lookahead.popFront();
			switch(lookahead.front.type) {
				// Identifier followed by ":", "=", "," or ")" are type parameters.
				case Colon, Equal, Comma, CloseParen :
					return trange.parseTypeParameter();
				
				case DotDotDot :
					auto name = trange.front.name;
					auto location = lookahead.front.location;
					
					import std.range;
					trange.popFrontN(2);
					return new AstTupleTemplateParameter(location, name);
				
				default :
					// We probably have a value parameter (or an error).
					return trange.parseValueParameter();
			}
		
		case Alias :
			return trange.parseAliasParameter();
		
		case This :
			auto location = trange.front.location;
			trange.popFront();
			
			auto name = trange.front.name;
			location.spanTo(trange.front.location);
			
			trange.match(Identifier);
			
			return new AstThisTemplateParameter(location, name);
		
		default :
			// We probably have a value parameter (or an error).
			return trange.parseValueParameter();
	}
}

private auto parseTypeParameter(ref TokenRange trange) {
	auto name = trange.front.name;
	auto location = trange.front.location;
	
	trange.match(TokenType.Identifier);
	
	AstType defaultType;
	switch(trange.front.type) with(TokenType) {
		case Colon :
			trange.popFront();
			auto specialization = trange.parseType();
			
			if(trange.front.type == Equal) {
				trange.popFront();
				defaultType = trange.parseType();
			}
			
			location.spanTo(trange.front.location);
			return new AstTypeTemplateParameter(location, name, specialization, defaultType);
		
		case Equal :
			trange.popFront();
			defaultType = trange.parseType();
			
			goto default;
		
		default :
			auto specialization = AstType.get(new BasicIdentifier(location, name));
			
			location.spanTo(trange.front.location);
			return new AstTypeTemplateParameter(location, name, specialization, defaultType);
	}
}

private auto parseValueParameter(ref TokenRange trange) {
	auto location = trange.front.location;
	
	auto type = trange.parseType();
	auto name = trange.front.name;
	
	location.spanTo(trange.front.location);
	trange.match(TokenType.Identifier);
	
	AstExpression defaultValue;
	if (trange.front.type == TokenType.Equal) {
		trange.popFront();
		switch(trange.front.type) with(TokenType) {
			case __File__, __Line__ :
				location.spanTo(trange.front.location);
				
				trange.popFront();
				break;
			
			default :
				defaultValue = trange.parseAssignExpression();
				location.spanTo(defaultValue.location);
		}
	}
	
	return new AstValueTemplateParameter(location, name, type, defaultValue);
}

private AstTemplateParameter parseAliasParameter(ref TokenRange trange) {
	auto location = trange.front.location;
	trange.match(TokenType.Alias);
	
	bool isTyped = false;
	if (trange.front.type != TokenType.Identifier) {
		isTyped = true;
	} else {
		// Identifier followed by ":", "=", "," or ")" are untyped alias parameters.
		auto lookahead = trange.save;
		lookahead.popFront();
		auto nextType = lookahead.front.type;
		switch(lookahead.front.type) with(TokenType) {
			case Colon, Equal, Comma, CloseParen :
				break;
			
			default:
				isTyped = true;
				break;
		}
	}
	
	if (isTyped) {
		auto type = trange.parseType();
		auto name = trange.front.name;
		
		location.spanTo(trange.front.location);
		trange.match(TokenType.Identifier);
		
		return new AstTypedAliasTemplateParameter(location, name, type);
	} else {
		auto name = trange.front.name;
		
		location.spanTo(trange.front.location);
		trange.match(TokenType.Identifier);
		
		return new AstAliasTemplateParameter(location, name);
	}
}

auto parseTemplateArguments(ref TokenRange trange) {
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
			auto identifier = new BasicIdentifier(trange.front.location, trange.front.name);
			arguments ~= new IdentifierTemplateArgument(identifier);
			
			trange.popFront();
			break;
		
		case True, False, Null, IntegerLiteral, StringLiteral, CharacterLiteral, FloatLiteral, __File__, __Line__ :
			arguments = [new ValueTemplateArgument(trange.parsePrimaryExpression())];
			break;
		
		/+
		case This :
			// This can be passed as alias parameter.
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

auto parseTemplateArgument(ref TokenRange trange) {
	auto location = trange.front.location;
	
	import d.parser.ambiguous;
	return trange.parseAmbiguous!(delegate TemplateArgument(parsed) {
		alias T = typeof(parsed);
		static if(is(T : AstType)) {
			location.spanTo(trange.front.location);
			return new TypeTemplateArgument(location, parsed);
		} else static if(is(T : AstExpression)) {
			return new ValueTemplateArgument(parsed);
		} else {
			return new IdentifierTemplateArgument(parsed);
		}
	})();
}
