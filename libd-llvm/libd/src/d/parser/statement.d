module d.parser.statement;

import d.ast.statement;

import d.parser.expression;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

auto parseStatement(TokenStream tstream) {
	switch(tstream.peek.type) {
		case TokenType.OpenBrace :
			return parseBlock(tstream);
		
		case TokenType.Return :
			tstream.get();
			parseExpression(tstream);
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

