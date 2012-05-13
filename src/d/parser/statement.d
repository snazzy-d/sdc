module d.parser.statement;

import d.ast.statement;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;

auto parseStatement(TokenStream tstream) {
	if(tstream.peek.type == TokenType.OpenBrace) {
		parseBlock(tstream);
	} else {
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

