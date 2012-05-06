module sdc.parser.sdctemplate2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;
import sdc.parser.declaration2;
import sdc.parser.type2;

auto parseTemplate(TokenStream tstream) {
	auto location = match(tstream, TokenType.Template).location;
	string name = match(tstream, TokenType.Identifier).value;
	
	auto parameters = parseTemplateParameters(tstream);
	
	parseAggregate(tstream);
	
	return null;
}

auto parseTemplateParameters(TokenStream tstream) {
	match(tstream, TokenType.OpenParen);
	
	typeof(null)[] parameters;
	
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

auto parseTemplateParameter(TokenStream tstream) {
	switch(tstream.peek.type) {
		case TokenType.Identifier :
			// Identifier followed by ":", "=", "," or ")" are type parameters.
			auto nextType = tstream.lookahead(1).type;
			if(nextType == TokenType.Colon || nextType == TokenType.Assign || nextType == TokenType.Comma || nextType == TokenType.CloseParen) {
				tstream.get();
				return null;
			}
			
			auto type = parseType(tstream);
			string name = match(tstream, TokenType.Identifier).value;
			
			// TODO: handle default parameter and specialisation.
			
			break;
		
		case TokenType.Alias :
			return parseAliasParameter(tstream);
		
		case TokenType.This :
			tstream.get();
			string name = match(tstream, TokenType.Identifier).value;
			
			return null;
		
		default :
			// TODO: handle error.
			assert(0);
	}
	
	assert(0);
}

auto parseAliasParameter(TokenStream tstream) {
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
	
	auto getParameter(bool isTyped)(TokenStream tstream) {
		static if(isTyped) {
			auto type = parseType(tstream);
		}
		
		match(tstream, TokenType.Identifier);
		
		if(tstream.peek.type == TokenType.Colon) {
			
		}
		
		if(tstream.peek.type == TokenType.Assign) {
			
		}
		
		return null;
	}
	
	if(isTyped) {
		return getParameter!true(tstream);
	} else {
		return getParameter!false(tstream);
	}
}

