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
	
	auto name = trange.front.name;
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
	
	AstTemplateParameter[] parameters;
	
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

private AstTemplateParameter parseTemplateParameter(TokenRange)(ref TokenRange trange) {
	switch(trange.front.type) with(TokenType) {
		case Identifier :
			auto lookahead = trange.save;
			lookahead.popFront();
			switch(lookahead.front.type) {
				// Identifier followed by ":", "=", "," or ")" are type parameters.
				case Colon, Assign, Comma, CloseParen :
					return trange.parseTypeParameter();
				
				case TripleDot :
					auto name = trange.front.name;
					auto location = lookahead.front.location;
					
					trange.popFrontN(2);
					return new AstTupleTemplateParameter(location, name);
				
				default :
					// We probably have a value parameter (or an error).
					return trange.parseValueParameter();
			}
		
		case Alias :
			return trange.parseAliasParameter();
		
		case This :
			Location location = trange.front.location;
			trange.popFront();
			
			auto name = trange.front.name;
			location.spanTo(trange.front.location);
			
			trange.match(Identifier);
			
			return new AstThisTemplateParameter(location, name);
		
		default :
			// We probably have a value parameter (or an error).
			// return trange.parseValueParameter();
			assert(0);
	}
}

private auto parseTypeParameter(TokenRange)(ref TokenRange trange) {
	auto name = trange.front.name;
	Location location = trange.front.location;
	
	trange.match(TokenType.Identifier);
	
	import d.ir.type;
	auto defaultType = QualAstType(new BuiltinType(TypeKind.None));
	switch(trange.front.type) with(TokenType) {
		case Colon :
			trange.popFront();
			auto specialization = trange.parseType();
			
			if(trange.front.type == Assign) {
				trange.popFront();
				defaultType = trange.parseType();
			}
			
			location.spanTo(trange.front.location);
			return new AstTypeTemplateParameter(location, name, specialization, defaultType);
		
		case Assign :
			trange.popFront();
			defaultType = trange.parseType();
			
			goto default;
		
		default :
			auto specialization = QualAstType(new IdentifierType(new BasicIdentifier(location, name)));
			
			location.spanTo(trange.front.location);
			return new AstTypeTemplateParameter(location, name, specialization, defaultType);
	}
}

private auto parseValueParameter(TokenRange)(ref TokenRange trange) {
	Location location = trange.front.location;
	
	auto type = trange.parseType();
	auto name = trange.front.name;
	
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
	
	return new AstValueTemplateParameter(location, name, type);
}

private AstTemplateParameter parseAliasParameter(TokenRange)(ref TokenRange trange) {
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

auto parseTemplateArgument(TokenRange)(ref TokenRange trange) if(isTokenRange!TokenRange) {
	auto location = trange.front.location;
	
	import d.parser.ambiguous;
	return trange.parseAmbiguous!(delegate TemplateArgument(parsed) {
		static if(is(typeof(parsed) : QualAstType)) {
			location.spanTo(trange.front.location);
			return new TypeTemplateArgument(location, parsed);
		} else static if(is(typeof(parsed) : AstExpression)) {
			return new ValueTemplateArgument(parsed);
		} else {
			return new IdentifierTemplateArgument(parsed);
		}
	})();
}

