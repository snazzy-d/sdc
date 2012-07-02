module d.parser.statement;

import d.ast.statement;

import d.parser.declaration;
import d.parser.expression;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

Statement parseStatement(TokenStream tstream) {
	switch(tstream.peek.type) {
		case TokenType.OpenBrace :
			return parseBlock(tstream);
		
		case TokenType.If :
			tstream.get();
			match(tstream, TokenType.OpenParen);
			auto condition = parseExpression(tstream);
			
			match(tstream, TokenType.CloseParen);
			
			parseStatement(tstream);
			
			if(tstream.peek.type == TokenType.Else) {
				parseStatement(tstream);
			}
			
			return null;
		
		case TokenType.While :
			tstream.get();
			match(tstream, TokenType.OpenParen);
			auto condition = parseExpression(tstream);
			
			match(tstream, TokenType.CloseParen);
			
			parseStatement(tstream);
			
			return null;
		
		case TokenType.Do :
			tstream.get();
			
			parseStatement(tstream);
			
			match(tstream, TokenType.While);
			match(tstream, TokenType.OpenParen);
			auto condition = parseExpression(tstream);
			
			match(tstream, TokenType.CloseParen);
			match(tstream, TokenType.Semicolon);
			
			return null;
		
		case TokenType.Return :
			tstream.get();
			if(tstream.peek.type != TokenType.Semicolon) {
				parseExpression(tstream);
			}
			
			match(tstream, TokenType.Semicolon);
			break;
		
		case TokenType.Throw :
			tstream.get();
			parseExpression(tstream);
			match(tstream, TokenType.Semicolon);
			break;
		
		default :
			tstream.get();
	}
	
	return null;
}

BlockStatement parseBlock(TokenStream tstream) {
	match(tstream, TokenType.OpenBrace);
	
	auto location = tstream.previous.location;
	
	Statement[] statements;
	
	while(tstream.peek.type != TokenType.CloseBrace) {
		statements ~= parseStatement(tstream);
	}
	
	location.spanTo(tstream.peek.location);
	
	tstream.get();
	
	return new BlockStatement(location, statements);
}

