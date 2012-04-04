module sdc.parser.type2;

import sdc.tokenstream;
import sdc.location;
import sdc.parser.base;
import sdc.ast.type2;

Type parseType(TokenStream tstream) {
	return parseBasicType(tstream);
}

auto parseBasicType(TokenStream tstream) {
	auto processQualifier(alias qualifyType)() {
		tstream.get();
		
		if(tstream.peek.type == TokenType.OpenParen) {
			tstream.get();
			auto type = parseType(tstream);
			match(tstream, TokenType.CloseParen);
			
			return qualifyType(type);
		} else {
			return qualifyType(parseType(tstream));
		}
	}
	
	switch(tstream.peek.type) {
		case TokenType.Const :
			return processQualifier!(function Type(type) { return type.makeConst(); })();
		default :
			// TODO: handle.
			assert(0);
	}
}

