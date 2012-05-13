module d.parser.dtemplate;

import d.ast.dtemplate;

import d.parser.declaration;
import d.parser.type;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

auto parseTemplate(TokenStream tstream) {
	auto location = match(tstream, TokenType.Template).location;
	
	string name = match(tstream, TokenType.Identifier).value;
	auto parameters = parseTemplateParameters(tstream);
	auto declarations = parseAggregate(tstream);
	
	location.spanTo(tstream.previous.location);
	
	return new TemplateDeclaration(location, name, parameters, declarations);
}

auto parseTemplateParameters(TokenStream tstream) {
	match(tstream, TokenType.OpenParen);
	
	TemplateParameter[] parameters;
	
	if(tstream.peek.type != TokenType.CloseParen) {
		parameters ~= parseTemplateParameter(tstream);
		
		while(tstream.peek.type != TokenType.CloseParen) {
			match(tstream, TokenType.Comma);
			
			parameters ~= parseTemplateParameter(tstream);
		}
	}
	
	match(tstream, TokenType.CloseParen);
	
	return parameters;
}

TemplateParameter parseTemplateParameter(TokenStream tstream) {
	switch(tstream.peek.type) {
		case TokenType.Identifier :
			// TODO: handle default parameter and specialisation.
			
			switch(tstream.lookahead(1).type) {
				// Identifier followed by ":", "=", "," or ")" are type parameters.
				case TokenType.Colon, TokenType.Assign, TokenType.Comma, TokenType.CloseParen :
					string name = tstream.peek.value;
					auto location = tstream.get().location;
					
					return new TypeTemplateParameter(location, name);
				
				case TokenType.TripleDot :
					string name = tstream.get().value;
					auto location = tstream.get().location;
					
					return new TupleTemplateParameter(location, name);
				
				default :
					break;
			}
			
			// We have a value parameter.
			goto default;
		
		case TokenType.Alias :
			return parseAliasParameter(tstream);
		
		case TokenType.This :
			auto location = tstream.get().location;
			string name = match(tstream, TokenType.Identifier).value;
			
			location.spanTo(tstream.previous.location);
			
			return new ThisTemplateParameter(location, name);
		
		default :
			// We probably have a value parameter (or an error).
			auto location = tstream.peek.location;
			
			auto type = parseType(tstream);
			string name = match(tstream, TokenType.Identifier).value;
			
			location.spanTo(tstream.previous.location);
			
			return new ValueTemplateParameter(location, name, type);
	}
}

TemplateParameter parseAliasParameter(TokenStream tstream) {
	auto location = match(tstream, TokenType.Alias).location;
	
	bool isTyped = false;
	if(tstream.peek.type != TokenType.Identifier) {
		isTyped = true;
	} else {
		// Identifier followed by ":", "=", "," or ")" are untype alias parameters.
		auto nextType = tstream.lookahead(1).type;
		if(nextType != TokenType.Colon && nextType != TokenType.Assign && nextType != TokenType.Comma && nextType != TokenType.CloseParen) {
			isTyped = true;
		}
	}
	
	if(isTyped) {
		auto type = parseType(tstream);
		string name = match(tstream, TokenType.Identifier).value;
		
		location.spanTo(tstream.previous.location);
		
		return new TypedAliasTemplateParameter(location, name, type);
	} else {
		string name = match(tstream, TokenType.Identifier).value;
		
		location.spanTo(tstream.previous.location);
		
		return new AliasTemplateParameter(location, name);
	}
}

