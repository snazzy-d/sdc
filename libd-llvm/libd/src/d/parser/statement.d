module d.parser.statement;

import d.ast.statement;

import d.parser.declaration;
import d.parser.expression;
import d.parser.util;

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
			
			break;
		
		case TokenType.While :
			tstream.get();
			match(tstream, TokenType.OpenParen);
			auto condition = parseExpression(tstream);
			
			match(tstream, TokenType.CloseParen);
			
			parseStatement(tstream);
			
			break;
		
		case TokenType.Do :
			tstream.get();
			
			parseStatement(tstream);
			
			match(tstream, TokenType.While);
			match(tstream, TokenType.OpenParen);
			auto condition = parseExpression(tstream);
			
			match(tstream, TokenType.CloseParen);
			match(tstream, TokenType.Semicolon);
			
			break;
		
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
		
		case TokenType.Mixin :
			tstream.get();
			match(tstream, TokenType.OpenParen);
			parseExpression(tstream);
			match(tstream, TokenType.CloseParen);
			match(tstream, TokenType.Semicolon);
			break;
		
		case TokenType.Auto :
			return parseDeclaration(tstream);
		
		default :
//*
			tstream.get();
/*/
			match(tstream, TokenType.Begin);
//*/
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

