module sdc.parser.statement2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base : match;
import sdc.ast.statement2;

auto parseStatement(TokenStream tstream) {
	return null;
}

auto parseBlock(TokenStream tstream) {
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

